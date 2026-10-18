#!/usr/bin/env python3
"""Plot a public terrain benchmark exported by terrainRealSantiagoBenchmark."""
import argparse
import json
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.colors import ListedColormap
import numpy as np

parser = argparse.ArgumentParser()
parser.add_argument("--input", required=True)
parser.add_argument("--output", required=True)
args = parser.parse_args()
data = json.loads(Path(args.input).read_text())
side = data["side"]
lon = np.array([p["longitude"] for p in data["positions"]]).reshape(side, side)
lat = np.array([p["latitude"] for p in data["positions"]]).reshape(side, side)
height = np.array([c["groundMeters"] if c else np.nan for c in data["cells"]]).reshape(side, side)
power = np.array([c["receivedPowerDBm"] if c else np.nan for c in data["cells"]]).reshape(side, side)
classification = np.where(np.isnan(power), np.nan, np.where(power < -110, 0, np.where(power < -100, 1, 2)))
fig, axes = plt.subplots(1, 3, figsize=(15, 6), constrained_layout=True)
terrain = axes[0].pcolormesh(lon, lat, height, shading="nearest", cmap="terrain", vmin=0, vmax=5500)
rx = axes[1].pcolormesh(lon, lat, power, shading="nearest", cmap="turbo", vmin=-155, vmax=-65)
coverage = axes[2].pcolormesh(lon, lat, classification, shading="nearest", cmap=ListedColormap(["#ffffff", "#f2ab44", "#2eb374"]), vmin=-0.5, vmax=2.5)
for ax in axes:
    ax.contour(lon, lat, height, levels=[500, 1000, 2000, 3000, 4000, 5000], colors="#273342", linewidths=0.4, alpha=0.5)
    ax.plot(data["origin"]["longitude"], data["origin"]["latitude"], "*", color="black", markersize=9)
    ax.set_aspect(1 / np.cos(np.radians(data["origin"]["latitude"])))
    ax.set_xlabel("Longitud · grados")
    ax.tick_params(labelsize=8)
axes[0].set_ylabel("Latitud · grados")
axes[0].set_title("Relieve usado en cada trayecto")
axes[1].set_title("Potencia RX · ITM punto a punto")
axes[2].set_title("Celdas con señal ≥−110 dBm")
fig.colorbar(terrain, ax=axes[0], shrink=0.65, label="Altitud de superficie · m AMSL")
fig.colorbar(rx, ax=axes[1], shrink=0.65, label="Potencia recibida estimada · dBm")
bar = fig.colorbar(coverage, ax=axes[2], shrink=0.65, ticks=[0, 1, 2])
bar.ax.set_yticklabels(["Bajo umbral", "Margen 0–10 dB", "Margen ≥10 dB"])
fig.suptitle("Santiago y los Andes · cobertura calculada con terreno real", fontsize=14)
fig.supxlabel(f"144,39 MHz · 10 W · antenas TX 10 m / RX 2 m AGL · área analizada 60 km\n"
              f"{data['covered']:,}/{data['modeled']:,} celdas sobre umbral · malla {data['cellSpacingMeters']:.0f} m · DEM {data['demSpacingMeters']:.0f} m/píxel\n"
              "Radio de 60 km: límite del análisis · Mapzen / USGS SRTM-GMTED / AWS · NTIA ITM · potencia estimada", fontsize=9)
destination = Path(args.output)
destination.parent.mkdir(parents=True, exist_ok=True)
fig.savefig(destination, dpi=180, facecolor="white")
plt.close(fig)
print(destination)
