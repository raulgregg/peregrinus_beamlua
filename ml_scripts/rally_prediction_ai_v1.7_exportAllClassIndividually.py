import os
# Disable oneDNN custom operations warning
os.environ["TF_ENABLE_ONEDNN_OPTS"] = "0"

import tensorflow as tf
from tensorflow.keras import layers
import pandas as pd
import numpy as np
from sklearn.preprocessing import MinMaxScaler
import gymnasium as gym
from stable_baselines3 import PPO
from stable_baselines3.common.vec_env import DummyVecEnv
import torch as th


device = "cpu"
print(f"Using device: {device}")

# Load dataset
data_path = "D:/Peregrinus/PereHobby/beamng/data/rally_training_data.csv"
df = pd.read_csv(data_path)

# Data cleaning
df = df.dropna().drop_duplicates()

# Feature selection
features = ["driver_name", "track_class", "car", "run", "checkpoint"]
parameters = ["risk", "vision", "awareness", "safety_distance", "lateral_offset_range", "lateral_offset_scale", "shortest_path_bias"]

df = df[features + parameters]
df.columns = df.columns.str.replace(" ", "_").str.lower()

# Perform dummy encoding on categorical columns
df = pd.get_dummies(df, columns=["driver_name", "track_class", "car"], drop_first=False)

# Normalize the parameter columns
scaler = MinMaxScaler()
df[parameters] = scaler.fit_transform(df[parameters])

# Define parameter limits for de-normalization
parameter_limits = {
    "risk": (0.4, 1.0),
    "vision": (0.5, 1.0),
    "awareness": (0.05, 0.10),
    "safety_distance": (0.01, 0.15),
    "lateral_offset_range": (0.5, 0.95),
    "lateral_offset_scale": (0.5, 1.0),
    "shortest_path_bias": (0.05, 1.0),
}

# Define the RL Environment
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

# Setup environment and RL model
env = DummyVecEnv([lambda: RallyEnv(df)])
model_path = "D:/Peregrinus/PereHobby/beamng/data/rally_ppo_model.zip"

if os.path.exists(model_path):
    model = PPO.load(model_path, env=env, device=device)
    print("Loaded existing PPO model for continued training.")
else:
    model = PPO("MlpPolicy", env, verbose=1, device=device)
    print("Created new PPO model for training.")

# Train the model and save
model.learn(total_timesteps=5000)
model.save(model_path)

# Process predictions per driver and per track class
# The dummy columns for track_class look like "track_class_ClassA", "track_class_ClassB", etc.
driver_columns = [col for col in df.columns if col.startswith("driver_name_")]

for driver_col in driver_columns:
    # Extract driver name from the dummy column name
    driver_name = driver_col.replace("driver_name_", "")
    driver_folder = f"D:/Peregrinus/PereHobby/beamng/data/RallySeries/{driver_name}"
    os.makedirs(driver_folder, exist_ok=True)
    
    # Filter rows for the given driver
    driver_df = df[df[driver_col] == 1]
    if driver_df.empty:
        continue

    # Group predictions by track class (determined from dummy columns)
    track_class_cols = [col for col in df.columns if col.startswith("track_class_")]
    predictions_by_class = {}
    metadata_by_class = {}  # To capture metadata (like run number) from the first row of each class

    for _, row in driver_df.iterrows():
        # Identify which track_class dummy column is active (assumes one-hot encoding)
        row_track_class = None
        for tc in track_class_cols:
            if row[tc] == 1:
                row_track_class = tc.replace("track_class_", "")
                break
        if row_track_class is None:
            continue
        
        # Initialize group if first time
        if row_track_class not in predictions_by_class:
            predictions_by_class[row_track_class] = []
            metadata_by_class[row_track_class] = row  # save first encountered row for metadata
        
        # Get the previous parameter values
        prev_params = row[parameters].to_dict()
        
        # Build input data for the model prediction:
        # Set the active track_class dummy column to 1 and include car dummy columns.
        track_dummy_col = "track_class_" + row_track_class
        input_dict = {**prev_params, track_dummy_col: 1}
        
        # Include all car columns (they should be the same as in df)
        car_cols = [col for col in df.columns if col.startswith("car_")]
        for col in car_cols:
            input_dict[col] = row[col]
        
        # Add the driver name dummy column for this driver
        input_dict["driver_name_" + driver_name] = 1
        
        # Create a DataFrame row and reindex to match df columns
        input_data = pd.DataFrame([input_dict])
        input_data = input_data.reindex(columns=df.columns, fill_value=0)
        
        input_values = input_data.astype(np.float32).values.flatten()
        
        obs = th.tensor(input_values[:env.observation_space.shape[0]], dtype=th.float32, device=device)
        assert obs.dtype in [th.float32, th.float64], f"Unexpected dtype in obs: {obs.dtype}"

        action, _ = model.predict(obs.cpu().numpy().astype(np.float32))

        # Compute suggested parameters based on action
        suggested_params = {}
        for i, param in enumerate(parameters):
            suggested_normalized = np.clip(prev_params[param] + action[i], 0.0, 1.0)
            suggested_original = suggested_normalized * (scaler.data_max_[i] - scaler.data_min_[i]) + scaler.data_min_[i]
            suggested_original_clipped = np.clip(suggested_original, *parameter_limits[param])
            suggested_params[param] = round(float(suggested_original_clipped), 4)
        
        predictions_by_class[row_track_class].append(suggested_params)
    
    # Save a separate CSV file for each track class for this driver
    for track_class, pred_list in predictions_by_class.items():
        meta_row = metadata_by_class[track_class]
        run_number = int(meta_row["run"])
        adjusted_run = max(1, run_number + 1)
        track_class_clean = track_class.replace(" ", "")
        driver_name_clean = driver_name.replace(" ", "")
        output_file_path = f"{driver_folder}/parameters_for_{track_class_clean}_run{adjusted_run}_{driver_name_clean}.csv"
        
        output_df = pd.DataFrame(pred_list)
        output_df.to_csv(output_file_path, index=False)
        print(f"Predictions saved for driver {driver_name_clean} and class {track_class_clean} in {output_file_path}")
