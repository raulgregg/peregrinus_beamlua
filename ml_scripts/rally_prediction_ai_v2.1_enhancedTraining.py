# ======================
# Environment Setup
# ======================
import os
os.environ["TF_ENABLE_ONEDNN_OPTS"] = "0"

import tensorflow as tf
from tensorflow.keras import layers
import pandas as pd
import numpy as np
from sklearn.preprocessing import MinMaxScaler
import gymnasium as gym
from stable_baselines3 import PPO
from stable_baselines3.common.vec_env import DummyVecEnv
from stable_baselines3.common.monitor import Monitor
from stable_baselines3.common.callbacks import BaseCallback, EvalCallback, CheckpointCallback
import torch as th
from typing import Dict, List, Tuple

# ======================
# Data Preparation
# ======================
# Load and combine all CSV files
data_path = "D:/Peregrinus/PereHobby/beamng/scripts/series_scripts/pereRally/ETL/csvFiles"
all_files = [os.path.join(data_path, f) for f in os.listdir(data_path) if f.endswith('.csv')]
df = pd.concat((pd.read_csv(f) for f in all_files), ignore_index=True)

# Manual input for run and training mode
run_value = int(input("Enter the correct integer value for 'run': "))
is_training_value = int(input("Enter the correct binary value (0 or 1) for 'is_training': "))
df["run"] = run_value
df["is_training"] = is_training_value

# Clean and preprocess data
df = df.dropna().drop_duplicates()
df.columns = df.columns.str.replace(" ", "_").str.lower()

# Define parameters and encode categorical features
parameters = [
    "risk", "vision", "awareness", "safetydistance", 
    "lateraloffsetrange", "lateraloffsetscale", 
    "shortestpathbias", "turnforcecoef", "springforceintegratordisplim"
]
df = pd.get_dummies(df, columns=["driver", "map_name", "stage_class"], drop_first=False)

# Feature engineering
df["time_delta"] = df.groupby([col for col in df.columns if col.startswith("driver_")])["time"].diff().fillna(0)
df["speed"] = 1 / (df["time_delta"] + 1e-6)

# Create feature set
driver_cols = [col for col in df.columns if col.startswith("driver_")]
map_cols = [col for col in df.columns if col.startswith("map_name_")]
class_cols = [col for col in df.columns if col.startswith("stage_class_")]
features = driver_cols + map_cols + class_cols + ["run", "is_training", "checkpoint", "multiplier", "speed", "time"]
df = df[features + parameters]

# Normalization
scaler = MinMaxScaler()
df[parameters + ["speed", "time"]] = scaler.fit_transform(df[parameters + ["speed", "time"]])
df[parameters + ["speed"]] = df[parameters + ["speed"]].astype(np.float32)

# Parameter limits for denormalization
parameter_limits = {
    "risk": (0.4, 1.2),
    "vision": (0.5, 1.0),
    "awareness": (0.05, 0.10),
    "safetydistance": (0.01, 0.15),
    "lateraloffsetrange": (0.5, 0.95),
    "lateraloffsetscale": (0.5, 1.0),
    "shortestpathbias": (0.05, 1.0),
    "turnforcecoef": (0.08, 0.1),
    "springforceintegratordisplim": (0.05, 0.25)
}

# ======================
# RL Environment Setup
# ======================
class RallyEnv(gym.Env):
    def __init__(self, df):
        super(RallyEnv, self).__init__()
        self.df = df.copy()
        self.current_index = 0
        self.action_space = gym.spaces.Box(low=-0.1, high=0.1, shape=(len(parameters),), dtype=np.float32)
        self.observation_space = gym.spaces.Box(low=0, high=1, shape=(len(features + parameters),), dtype=np.float32)

    def reset(self, seed=None, options=None):
        self.current_index = 0
        return self._get_observation(), {}

    def step(self, action):
        if self.current_index >= len(self.df) - 1:
            return np.zeros(self.observation_space.shape), 0, True, False, {}
        
        # Apply parameter adjustments
        prev_params = self.df.iloc[self.current_index][parameters].copy()
        new_params = np.clip(prev_params.values + action.astype(np.float32), 0, 1).astype(np.float32)
        self.df.iloc[self.current_index, -len(parameters):] = new_params

        # Calculate rewards
        current_row = self.df.iloc[self.current_index]
        next_row = self.df.iloc[self.current_index + 1]
        time_delta = next_row["time"] - current_row["time"]
        reward = (1 / (time_delta + 1e-6)) * current_row["multiplier"]
        reward -= 0.01 * np.sum(np.square(action))  # Safety penalty
        
        self.current_index += 1
        done = self.current_index >= len(self.df) - 1
        return self._get_observation(), reward, done, False, {}

    def _get_observation(self):
        row = self.df.iloc[self.current_index]
        return np.concatenate([row[features].values, row[parameters].values]).astype(np.float32)

# ======================
# Training Configuration
# ======================
device = "cpu"
print(f"Using device: {device}")

# Initialize environment
env = DummyVecEnv([lambda: Monitor(RallyEnv(df))])
model_path = "D:/Peregrinus/PereHobby/beamng/scripts/series_scripts/pereRally/ETL/rally_ppo_model"
model_file = f"{model_path}.zip" 

# Load or create model
if os.path.exists(model_file):
    try:
        model = PPO.load(model_file, env=env, device=device)
        print("Loaded existing model for continued training.")
    except PermissionError:
        print(f"Permission denied for {model_file}. Solutions:")
        print("1. Close any programs using this file")
        print("2. Run script as administrator")
        print("3. Check antivirus restrictions")
        print("Creating new model instead...")
        model = PPO("MlpPolicy", env, **your_parameters)
else:
    model = PPO("MlpPolicy", env, **your_parameters)
    print("Created new model.")

# Model architecture
policy_kwargs = dict(
    activation_fn=th.nn.ReLU,
    net_arch=dict(pi=[256, 256, 256, 128, 128], vf=[256, 256, 256, 128, 128])
)

# Load or create model
if os.path.exists(model_file):
    model = PPO.load(model_file, env=env, device=device)
    print("Loaded existing model for continued training.")
else:
    model = PPO(
        "MlpPolicy",
        env,
        verbose=1,
        device=device,
        policy_kwargs=policy_kwargs,
        learning_rate=3e-4,
        n_steps=2048,
        batch_size=64,
        n_epochs=10,
        gamma=0.99,
        gae_lambda=0.95,
        clip_range=0.2,
        ent_coef=0.01
    )
    print("Created new model.")

# ======================
# Enhanced Training Setup
# ======================
class SaveBestModelCallback(BaseCallback):
    def __init__(self, check_freq, save_path, verbose=1):
        super().__init__(verbose)
        self.check_freq = check_freq
        self.save_path = save_path
        self.best_mean_reward = -np.inf

    def _on_step(self):
        if self.n_calls % self.check_freq == 0:
            if len(self.model.ep_info_buffer) > 0:
                mean_reward = np.mean([ep_info["r"] for ep_info in self.model.ep_info_buffer])
                if mean_reward > self.best_mean_reward:
                    self.best_mean_reward = mean_reward
                    self.model.save(f"{self.save_path}_best")
                    print(f"New best model: {self.best_mean_reward:.2f}")
        return True

# Configure callbacks
eval_env = DummyVecEnv([lambda: Monitor(RallyEnv(df))])
callbacks = [
    EvalCallback(
        eval_env,
        best_model_save_path=os.path.join(model_path, "best_eval"),
        log_path=os.path.join(model_path, "logs"),
        eval_freq=1000,
        deterministic=True,
        render=False
    ),
    CheckpointCallback(
        save_freq=500,
        save_path=os.path.join(model_path, "checkpoints"),
        name_prefix="rally_model"
    ),
    SaveBestModelCallback(
        check_freq=500,
        save_path=os.path.join(model_path, "best_train")
    )
]

# Execute training
model.learn(
    total_timesteps=5000, # change it to 100000 when starting it seriously
    callback=callbacks,
    progress_bar=True,
    tb_log_name="ppo_rally",
    reset_num_timesteps=not os.path.exists(f"{model_path}.zip")
)
model.save(model_path)

# ======================
# Prediction & Output
# ======================
driver_columns = [col for col in df.columns if col.startswith("driver_")]
stage_class_cols = [col for col in df.columns if col.startswith("stage_class_")]

for driver_col in driver_columns:
    driver = driver_col.replace("driver_", "")
    driver_folder = f"D:/Peregrinus/PereHobby/beamng/data/RallySeries/{driver}"
    os.makedirs(driver_folder, exist_ok=True)
    
    driver_df = df[df[driver_col] == 1].copy()
    if driver_df.empty:
        continue

    predictions_by_class = {}
    metadata_by_class = {}

    for _, row in driver_df.iterrows():
        active_class = next((sc_col.replace("stage_class_", "") for sc_col in stage_class_cols if row[sc_col] == 1), None)
        if not active_class:
            continue

        if active_class not in predictions_by_class:
            predictions_by_class[active_class] = []
            metadata_by_class[active_class] = row

        input_dict = {**row[parameters].to_dict(), **{col: row[col] for col in features}, driver_col: 1}
        input_data = pd.DataFrame([input_dict]).reindex(columns=df.columns, fill_value=0)
        obs = input_data.astype(np.float32).values.flatten()[:env.observation_space.shape[0]]
        
        try:
            action, _ = model.predict(obs, deterministic=True)
            suggested_params = {}
            for i, param in enumerate(parameters):
                min_val, max_val = parameter_limits[param]
                norm_val = np.clip(row[param] + action[i], 0, 1)
                suggested_params[param] = round(norm_val * (max_val - min_val) + min_val, 4)
            predictions_by_class[active_class].append(suggested_params)
        except Exception as e:
            print(f"Prediction error: {str(e)}")
            continue

    # Save predictions
    for stage_class, pred_list in predictions_by_class.items():
        if not pred_list:
            continue
            
        meta_row = metadata_by_class[stage_class]
        map_cols = [col for col in df.columns if col.startswith("map_name_")]
        map_name = next((col.replace("map_name_", "") for col in map_cols if meta_row[col] == 1), "Unknown")
        
        output_path = f"{driver_folder}/params_{map_name}_{stage_class}_run{meta_row['run']+1}_{driver}.csv"
        pd.DataFrame(pred_list).to_csv(output_path, index=False)
        print(f"Saved {len(pred_list)} predictions to {output_path}")