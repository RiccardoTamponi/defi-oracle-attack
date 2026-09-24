import sqlite3
import matplotlib.pyplot as plt

DB = "analysis/data/defi_sok.db"
ORACLE_CAUSE = 23  # "On-chain oracle manipulation" nella tassonomia SoK

con = sqlite3.connect(DB)

def q(sql, params=()):
    return con.execute(sql, params).fetchall()

tot_n, tot_dmg = q("SELECT COUNT(*), SUM(avg_reported_damage_in_usd) FROM Incident")[0]

orc_n, orc_dmg = q("""
    SELECT COUNT(DISTINCT i.incident_id), SUM(i.avg_reported_damage_in_usd)
    FROM Incident i
    JOIN IncidentCause ic ON ic.incident_id = i.incident_id
    WHERE ic.cause_id = ?""", (ORACLE_CAUSE,))[0]

print(f"Incidenti totali: {tot_n}, danno {tot_dmg / 1e6:.1f} M USD")
print(f"Oracle manipulation on-chain: {orc_n} incidenti ({orc_n / tot_n:.1%}), "
      f"danno {orc_dmg / 1e6:.1f} M USD ({orc_dmg / tot_dmg:.1%})")

top = q("""
    SELECT c.cause_id, c.cause_title, COUNT(DISTINCT ic.incident_id) AS n
    FROM IncidentCause ic
    JOIN Cause c ON c.cause_id = ic.cause_id
    GROUP BY c.cause_id
    ORDER BY n DESC
    LIMIT 10""")
top = top[::-1]  # barh disegna dal basso: invertiamo per avere la piu' frequente in cima

plt.figure(figsize=(9, 5))
plt.barh([t[1] for t in top], [t[2] for t in top],
         color=["tab:red" if t[0] == ORACLE_CAUSE else "tab:gray" for t in top])
plt.xlabel("numero di incidenti")
plt.title("Le 10 cause piu' frequenti negli attacchi DeFi (SoK, 2018-2022)")
plt.tight_layout()
plt.savefig("analysis/dataset_top_causes.png", dpi=150)


years = q("""
    SELECT substr(i.incident_date, 1, 4) AS y,
           COUNT(*),
           SUM(EXISTS (SELECT 1 FROM IncidentCause ic
                       WHERE ic.incident_id = i.incident_id AND ic.cause_id = ?))
    FROM Incident i
    GROUP BY y
    ORDER BY y""", (ORACLE_CAUSE,))

x = range(len(years))
plt.figure(figsize=(8, 4.5))
plt.bar([i - 0.2 for i in x], [r[1] for r in years], width=0.4,
        label="tutti gli incidenti", color="tab:gray")
plt.bar([i + 0.2 for i in x], [r[2] for r in years], width=0.4,
        label="oracle manipulation on-chain", color="tab:red")
plt.xticks(list(x), [r[0] for r in years])
plt.ylabel("numero di incidenti")
plt.title("Incidenti per anno")
plt.legend()
plt.tight_layout()
plt.savefig("analysis/dataset_per_year.png", dpi=150)
print("Grafici salvati in analysis/")
