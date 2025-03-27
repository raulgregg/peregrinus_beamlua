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
env = DummyVecEnv([lambda: RallyEnv(df)])
model = PPO("MlpPolicy", env, verbose=1, device=device)
model.learn(total_timesteps=10000)
model.save("D:/Peregrinus/PereHobby/beamng/data/rally_ppo_model")

# Function to suggest new parameters using RL model
def suggest_parameters_rl(driver, track, car, prev_params):
    input_data = pd.DataFrame([{**prev_params, "driver_name": driver, "track_class": track, "car": car}])
    input_data = pd.get_dummies(input_data, columns=["driver_name", "track_class", "car"], drop_first=False)
    input_data = input_data.reindex(columns=df.columns, fill_value=0)
    obs = th.tensor(input_data.values.flatten()[:env.observation_space.shape[0]], dtype=th.float32, device=device)
    action, _ = model.predict(obs.cpu().numpy())
    return {param: np.clip(prev_params[param] + action[i], 0, 1) for i, param in enumerate(parameters)}

# Process suggestions for each driver
unique_drivers = df.columns[df.columns.str.startswith("driver_name_")]
for driver in unique_drivers:
    driver_name = driver.replace("driver_name_", "")
    driver_folder = f"D:/Peregrinus/PereHobby/beamng/data/RallySeries/{driver_name}"
    os.makedirs(driver_folder, exist_ok=True)
    output_file_path = f"{driver_folder}/suggested_parameters_{driver_name}.csv"
    driver_df = df[df[driver] == 1]
    suggested_params_list = []
    
    for _, row in driver_df.iterrows():
        prev_params = row[parameters].to_dict()
        
        # Extract the encoded track_class columns
        track_class_cols = [col for col in df.columns if col.startswith("track_class_")]
        track_class_values = {col: row[col] for col in track_class_cols}
        
        # Extract the encoded car columns
        car_cols = [col for col in df.columns if col.startswith("car_")]
        car_values = {col: row[col] for col in car_cols}
        
        # Combine the parameters
        input_data = {**prev_params, **track_class_values, **car_values, "driver_name": driver_name}
        input_data = pd.DataFrame([input_data])
        
        # Ensure the input data has the same columns as the training data
        input_data = input_data.reindex(columns=df.columns, fill_value=0)
        
        obs = th.tensor(input_data.values.flatten()[:env.observation_space.shape[0]], dtype=th.float32, device=device)
        action, _ = model.predict(obs.cpu().numpy())
        
        suggested_params = {param: np.clip(prev_params[param] + action[i], 0, 1) for i, param in enumerate(parameters)}
        suggested_params_list.append(suggested_params)
    
    output_df = pd.DataFrame(suggested_params_list)
    output_df.to_csv(output_file_path, index=False)
    print(f"Suggested Parameters saved for {driver_name} in {output_file_path}")