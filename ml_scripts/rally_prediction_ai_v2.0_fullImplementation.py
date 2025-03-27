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
from stable_baselines3.common.callbacks import BaseCallback
import torch as th
from typing import Dict, List, Tuple

# Load dataset from all CSV files
data_path = "D:/Peregrinus/PereHobby/beamng/scripts/series_scripts/pereRally/ETL/csvFiles"
all_files = [os.path.join(data_path, f) for f in os.listdir(data_path) if f.endswith('.csv')]
df = pd.concat((pd.read_csv(f) for f in all_files), ignore_index=True)

# Manual input for run and is_training
run_value = int(input("Enter the correct integer value for 'run': "))
is_training_value = int(input("Enter the correct binary value (0 or 1) for 'is_training': "))
df["run"] = run_value
df["is_training"] = is_training_value

# Data cleaning and preprocessing
df = df.dropna().drop_duplicates()
df.columns = df.columns.str.replace(" ", "_").str.lower()

parameters = [
    "risk", "vision", "awareness", "safetydistance", 
    "lateraloffsetrange", "lateraloffsetscale", 
    "shortestpathbias", "turnforcecoef", "springforceintegratordisplim"
]

df = pd.get_dummies(df, columns=["driver", "map_name", "stage_class"], drop_first=False)

# Then do feature engineering
df["time_delta"] = df.groupby([col for col in df.columns if col.startswith("driver_")])["time"].diff().fillna(0)
df["speed"] = 1 / (df["time_delta"] + 1e-6)

# Update features list to use dummy columns
driver_cols = [col for col in df.columns if col.startswith("driver_")]
map_cols = [col for col in df.columns if col.startswith("map_name_")]
class_cols = [col for col in df.columns if col.startswith("stage_class_")]

features = driver_cols + map_cols + class_cols + [
    "run", "is_training", "checkpoint", "multiplier", "speed"
]

# Now select only numerical features
df = df[features + parameters]

# Enhanced normalization with speed
scaler = MinMaxScaler()
df[parameters + ["speed"]] = scaler.fit_transform(df[parameters + ["speed"]])
df[parameters + ["speed"]] = df[parameters + ["speed"]].astype(np.float32)

# Updated parameter limits based on your data
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

device = "cpu"
print(f"Using device: {device}")

class RallyEnv(gym.Env):
    """Enhanced rally environment with better reward shaping"""
    
    def __init__(self, df: pd.DataFrame):
        super(RallyEnv, self).__init__()
        self.df = df.copy()
        self.current_index = 0
        self.action_space = gym.spaces.Box(
            low=-0.1, 
            high=0.1, 
            shape=(len(parameters),), 
            dtype=np.float32
        )
        self.observation_space = gym.spaces.Box(
            low=0, 
            high=1, 
            shape=(len(features + parameters),),  # Should now match the actual number of numerical features
            dtype=np.float32
        )
    def _get_observation(self) -> np.ndarray:
        """Get current observation with encoded features"""
        return self.df.iloc[self.current_index][features + parameters].values.astype(np.float32)
        
    def reset(self, seed=None, options=None):
        self.current_index = 0
        observation = self._get_observation()
        return observation, {}
    
    def step(self, action: np.ndarray):
        if self.current_index >= len(self.df) - 1:
            return np.zeros(self.observation_space.shape), 0, True, False, {}
            
        # Apply action to parameters
        current_params = self.df.iloc[self.current_index][parameters].values.astype(np.float32)
        new_params = np.clip(current_params + action.astype(np.float32), 0, 1).astype(np.float32)
        self.df.iloc[self.current_index, -len(parameters):] = new_params
        
        # Calculate reward based on speed improvement
        prev_speed = self.df.iloc[self.current_index]["speed"]
        self.current_index += 1
        new_speed = self.df.iloc[self.current_index]["speed"]
        
        # Reward is combination of speed improvement and parameter safety
        speed_reward = new_speed - prev_speed
        safety_penalty = -0.1 * np.sum(np.abs(action))  # Penalize large parameter changes
        reward = speed_reward + safety_penalty
        
        done = self.current_index >= len(self.df) - 1
        observation = self._get_observation()
        
        return observation, reward, done, False, {}
    
    def _get_observation(self) -> np.ndarray:
        """Get current observation with all features and parameters"""
        return self.df.iloc[self.current_index][features + parameters].values.astype(np.float32)

class SaveBestModelCallback(BaseCallback):
    """Callback to save the best model based on reward"""
    def __init__(self, check_freq: int, save_path: str, verbose=1):
        super(SaveBestModelCallback, self).__init__(verbose)
        self.check_freq = check_freq
        self.save_path = save_path
        self.best_mean_reward = -np.inf

    def _on_step(self) -> bool:
        if self.n_calls % self.check_freq == 0:
            if len(self.model.ep_info_buffer) > 0:  # Check for empty buffer
                mean_reward = np.mean([ep_info["r"] for ep_info in self.model.ep_info_buffer if "r" in ep_info])
                if mean_reward > self.best_mean_reward:
                    self.best_mean_reward = mean_reward
                    self.model.save(f"{self.save_path}_best")
                    print(f"New best model: Avg reward {self.best_mean_reward:.2f}")
            else:
                print("No episodes completed yet")
        return True

# Setup environment
env = DummyVecEnv([lambda: RallyEnv(df)])
model_path = "D:/Peregrinus/PereHobby/beamng/scripts/series_scripts/pereRally/ETL/rally_ppo_model"

# Model configuration with updated hyperparameters
policy_kwargs = dict(
    activation_fn=th.nn.ReLU,
    net_arch=dict(pi=[256, 256, 256, 128, 128], vf=[256, 256, 256, 128, 128])
)

if os.path.exists(f"{model_path}.zip"):
    model = PPO.load(model_path, env=env, device=device)
    print("Loaded existing PPO model for continued training.")
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
    print("Created new PPO model for training.")

# Train with callback
callback = SaveBestModelCallback(check_freq=1000, save_path=model_path)
model.learn(total_timesteps=5000, callback=callback)
model.save(model_path)

# Process predictions per driver and per track class
# The dummy columns for track_class look like "track_class_ClassA", "track_class_ClassB", etc.
driver_columns = [col for col in df.columns if col.startswith("driver_")]
stage_class_cols = [col for col in df.columns if col.startswith("stage_class_")]

for driver_col in driver_columns:
    driver = driver_col.replace("driver_", "")
    driver_folder = f"D:/Peregrinus/PereHobby/beamng/data/RallySeries/{driver}"
    os.makedirs(driver_folder, exist_ok=True)
    
    # Filter driver data with proper dtype handling
    driver_df = df[df[driver_col] == 1].copy()
    if driver_df.empty:
        print(f"No data found for driver {driver}, skipping...")
        continue

    predictions_by_class = {}
    metadata_by_class = {}

    for idx, row in driver_df.iterrows():
        # Identify active stage class
        active_class = None
        for sc_col in stage_class_cols:
            if row[sc_col] == 1:
                active_class = sc_col.replace("stage_class_", "")
                break
                
        if not active_class:
            print(f"No stage class found for row {idx}, skipping...")
            continue

        # Initialize class group if needed
        if active_class not in predictions_by_class:
            predictions_by_class[active_class] = []
            metadata_by_class[active_class] = row

        # Build input data with proper feature columns
        input_dict = {
            **row[parameters].to_dict(),
            **{col: row[col] for col in features if col in row},
            driver_col: 1
        }
        
        # Create input DataFrame with correct columns
        input_data = pd.DataFrame([input_dict]).reindex(columns=df.columns, fill_value=0)
        input_values = input_data.astype(np.float32).values.flatten()
        
        # Ensure observation matches environment specs
        obs = input_values[:env.observation_space.shape[0]]
        
        try:
            action, _ = model.predict(obs, deterministic=True)
            # Denormalize parameters using original scaler ranges
            suggested_params = {}
            for i, param in enumerate(parameters):
                min_val, max_val = parameter_limits[param]
                suggested_normalized = np.clip(row[param] + action[i], 0, 1)
                suggested_original = suggested_normalized * (max_val - min_val) + min_val
                suggested_params[param] = round(float(suggested_original), 4)
            
            predictions_by_class[active_class].append(suggested_params)
        except Exception as e:
            print(f"Prediction failed for {driver} class {active_class}: {str(e)}")
            continue

    # Save CSVs for valid predictions
    for stage_class, pred_list in predictions_by_class.items():
        if not pred_list:
            print(f"No predictions for {driver} class {stage_class}")
            continue
            
        meta_row = metadata_by_class[stage_class]
        run_number = int(meta_row["run"])
        adjusted_run = max(1, run_number + 1)
        
        # Get map name from dummy columns
        map_cols = [col for col in df.columns if col.startswith("map_name_")]
        active_map = [col.replace("map_name_", "") for col in map_cols if meta_row[col] == 1]
        map_name = active_map[0] if len(active_map) > 0 else "UnknownMap"

        # Clean names for filenames
        stage_class_clean = stage_class.replace(" ", "")
        driver_clean = driver.replace(" ", "")
        
        output_path = f"{driver_folder}/params_{map_name}_{stage_class_clean}_run{adjusted_run}_{driver_clean}.csv"
        
        pd.DataFrame(pred_list).to_csv(output_path, index=False)
        print(f"Saved {len(pred_list)} predictions to {output_path}")
