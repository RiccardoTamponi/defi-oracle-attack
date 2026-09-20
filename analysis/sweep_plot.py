import csv
from collections import defaultdict
import matplotlib.pyplot as plt

WAD = 1e18

# Raggruppa i punti per collateral factor
series = defaultdict(list)  # cf -> lista di (ratio, profitto_ETH)
with open("analysis/sweep_results.csv") as f:
    for row in csv.DictReader(f):
        cf     = int(row["cf_wad"]) / WAD
        ratio  = int(row["ratio_permille"]) / 1000
        profit = (int(row["borrowable_wei"]) - int(row["dx_wei"])) / WAD
        series[cf].append((ratio, profit))

plt.figure(figsize=(8, 5))
for cf in sorted(series):
    pts = sorted(series[cf])
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    plt.plot(xs, ys, marker="o", label=f"cf = {cf:.3f}")

plt.axhline(0, color="black", linewidth=1)          # confine profitto = 0
plt.xlabel("dimensione del pump  dx / X")
plt.ylabel("profitto dell'attaccante (ETH)")
plt.title("Profittabilita' dell'attacco vs pump e collateral factor")
plt.legend(title="collateral factor")
plt.grid(True, alpha=0.3)
plt.tight_layout()

plt.savefig("analysis/sweep_profit.png", dpi=150)
print("Grafico salvato -> analysis/sweep_profit.png")

