import os
# Disable oneDNN custom operations warning
os.environ["TF_ENABLE_ONEDNN_OPTS"] = "0"

import tensorflow as tf
from tensorflow.keras import layers
import pandas as pd
import numpy as np
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import MinMaxScaler
import gymnasium as gym
from stable_baselines3 import PPO
from stable_baselines3.common.vec_env import DummyVecEnv
import torch as th

# Ensure NumPy compatibility
import numpy as np
if int(np.__version__.split(".")[0]) >= 2:
    raise RuntimeError("NumPy 2.x detected. Please downgrade to NumPy 1.x using: pip install numpy<2")

# Check GPU availability
#device = "cuda" if tf.config.list_physical_devices('GPU') else "cpu"
device = "cpu"
print(f"Using device: {device}")

# Load dataset
data_path = "D:/Peregrinus/PereHobby/beamng/data/rally_training_data.csv"
df = pd.read_csv(data_path)

# Data Cleaning
df = df.dropna().drop_duplicates()

# Feature selection
features = ["driver_name", "track_class", "car", "run", "checkpoint"]
parameters = ["risk", "vision", "awareness", "safety_distance", "lateral_offset_range", "lateral_offset_scale", "shortest_path_bias"]

df = df[features + parameters]
df.columns = df.columns.str.replace(" ", "_").str.lower()

# Encode categorical variables
df = pd.get_dummies(df, columns=["driver_name", "track_class", "car"], drop_first=False)

# Normalize the parameters
scaler = MinMaxScaler()
df[parameters] = scaler.fit_transform(df[parameters])

# Define parameter limits
parameter_limits = {
    "risk": (0.4, 1.0),
    "vision": (0.5, 1.0),
    "awareness": (0.05, 0.10),
    "safety_distance": (0.01, 0.15),
    "lateral_offset_range": (0.5, 0.95),
    "lateral_offset_scale": (0.5, 1.0),
    "shortest_path_bias": (0.05, 1.0),
}

# Define Reinforcement Learning Environment
class RallyEnv(gym.Env):
    def __init__(self, df):
        super(RallyEnv, self).__init__()
        self.df = df
        self.current_index = 0
        self.action_space = gym.spaces.Box(low=-0.1, high=0.1, shape=(len(parameters),), dtype=np.float32)
        self.observation_space = gym.spaces.Box(low=0, high=1, shape=(df.shape[1] - 1,), dtype=np.float32)
        
    def reset(self, seed=None, options=None):
        self.current_index = 0
        self.state = self.df.iloc[self.current_index].values[:-1].astype(np.float32)
        return self.state, {}

    def step(self, action):
        prev_time = self.df.iloc[self.current_index]["checkpoint"]
        self.df.iloc[self.current_index, -len(parameters):] += action
        self.df.iloc[self.current_index, -len(parameters):] = np.clip(self.df.iloc[self.current_index, -len(parameters):], 0, 1)
        new_time = self.df.iloc[self.current_index]["checkpoint"]
        reward = prev_time - new_time
        done = self.current_index >= len(self.df) - 1
        self.current_index += 1

        next_state = self.df.iloc[self.current_index, :-1].values.astype(np.float32) if not done else np.zeros(self.observation_space.shape, dtype=np.float32)
        return next_state, reward, done, False, {}

# Train PPO Model
policy_kwargs = dict(
    net_arch=dict(pi=[128, 128, 128, 128], vf=[128, 128, 128, 128])
)
env = DummyVecEnv([lambda: RallyEnv(df)])
model = PPO("MlpPolicy", env, verbose=1, device=device, policy_kwargs=policy_kwargs)
model.learn(total_timesteps=10000)
model.save("D:/Peregrinus/PereHobby/beamng/data/rally_ppo_model")

# Function to suggest new parameters using RL model
def suggest_parameters_rl(driver, track, car, prev_params):
    input_data = pd.DataFrame([{**prev_params, "driver_name": driver, "track_class": track, "car": car}])
    input_data = pd.get_dummies(input_data, columns=["driver_name", "track_class", "car"], drop_first=False)
    input_data = input_data.reindex(columns=df.columns, fill_value=0)
    
    input_values = input_data.astype(np.float32).values.flatten()
    
    obs = th.tensor(input_values[:env.observation_space.shape[0]], dtype=th.float32, device=device)
    action, _ = model.predict(obs.cpu().numpy())
    
    suggested_params = {}
    for i, param in enumerate(parameters):
        # Apply action in normalized space and clip
        suggested_normalized = prev_params[param] + action[i]
        suggested_normalized = np.clip(suggested_normalized, 0.0, 1.0)
        
        # Denormalize to original scale
        data_min = scaler.data_min_[i]
        data_max = scaler.data_max_[i]
        suggested_original = suggested_normalized * (data_max - data_min) + data_min
        
        # Apply parameter limits and rounding
        min_val, max_val = parameter_limits[param]
        suggested_original_clipped = np.clip(suggested_original, min_val, max_val)
        suggested_params[param] = round(float(suggested_original_clipped), 4)
    
    return suggested_params

# Process suggestions for each driver
unique_drivers = df.columns[df.columns.str.startswith("driver_name_")]
for driver in unique_drivers:
    driver_name = driver.replace("driver_name_", "")
    driver_folder = f"D:/Peregrinus/PereHobby/beamng/data/RallySeries/{driver_name}"
    os.makedirs(driver_folder, exist_ok=True)
    driver_df = df[df[driver] == 1]
    suggested_params_list = []

    try:
        # Get metadata from first row with error handling
        first_row = driver_df.iloc[0]
        
        # Extract track class with tolerance and fallback
        track_class_cols = [col for col in df.columns if col.startswith("track_class_")]
        track_class = [col.replace("track_class_", "") for col in track_class_cols 
                      if np.isclose(first_row[col], 1.0, atol=0.01)]  # Increased tolerance
        
        if not track_class:
            # Fallback to first existing track class
            track_class = [col.replace("track_class_", "") for col in track_class_cols 
                          if col in driver_df.columns][0]
        else:
            track_class = track_class[0]

        #Space clean
        track_class_clean = track_class.replace(" ", "")  # Remove spaces
        driver_name_clean = driver_name.replace(" ", "") # Remove spaces

        # Get run number with validation
        run_number = int(first_row["run"])
        adjusted_run = max(1, run_number + 1)  # Ensure minimum run 1
        
        # Create filename
        output_file_path = f"{driver_folder}/parameters_for_{track_class_clean}_run{adjusted_run}_{driver_name_clean}.csv"
        
    except Exception as e:
        print(f"Skipping driver {driver_name} due to metadata error: {str(e)}")
        continue
    
    # Rest of the processing remains the same
    for _, row in driver_df.iterrows():
        prev_params = row[parameters].to_dict()
        
        track_class_cols = [col for col in df.columns if col.startswith("track_class_")]
        track_class_values = {col: row[col] for col in track_class_cols}

        car_cols = [col for col in df.columns if col.startswith("car_")]
        car_values = {col: row[col] for col in car_cols}
        
        input_data = {**prev_params, **track_class_values, **car_values, "driver_name": driver_name}
        input_data = pd.DataFrame([input_data])
        
        input_data = input_data.reindex(columns=df.columns, fill_value=0)
        
        obs = th.tensor(input_data.values.flatten()[:env.observation_space.shape[0]], dtype=th.float32, device=device)
        action, _ = model.predict(obs.cpu().numpy())
        
        suggested_params = {}
        for i, param in enumerate(parameters):
            # Apply action in normalized space and clip
            suggested_normalized = prev_params[param] + action[i]
            suggested_normalized = np.clip(suggested_normalized, 0.0, 1.0)
            
            # Denormalize to original scale
            data_min = scaler.data_min_[i]
            data_max = scaler.data_max_[i]
            suggested_original = suggested_normalized * (data_max - data_min) + data_min
            
            # Apply parameter limits in original scale
            min_val, max_val = parameter_limits[param]
            suggested_original_clipped = np.clip(suggested_original, min_val, max_val)
            suggested_params[param] = suggested_original_clipped
        
        suggested_params_list.append(suggested_params)
    
    output_df = pd.DataFrame(suggested_params_list)
    output_df.to_csv(output_file_path, index=False)
    print(f"Parameters saved for {driver_name}")