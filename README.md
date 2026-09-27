# DeFi Oracle Attack

Simulazione locale, in Solidity con [Foundry](https://getfoundry.sh/), di un attacco di
**oracle manipulation tramite flash loan**, ispirato all'attacco a bZx del 18 febbraio
2020. Il progetto studia quando l'attacco è profittevole, quanto rende, come lo si
neutralizza con un oracolo TWAP, e ne motiva la scelta con i dati reali del dataset SoK
sugli attacchi DeFi.

## L'attacco in breve

Tutto avviene in **una sola transazione atomica**:

1. l'attaccante prende in prestito ETH con un **flash loan**;
2. con una parte fa il **pump**: scambia ETH per sUSD su un AMM a prodotto costante
   (`x·y = k`), e il prezzo di sUSD sull'AMM sale;
3. con il resto compra sUSD **a prezzo giusto** su un secondo mercato, che l'oracolo non
   legge;
4. deposita **tutti** gli sUSD come collaterale in un protocollo di lending che legge il
   prezzo **spot** dall'AMM;
5. il lending valuta tutto il collaterale al prezzo gonfiato e presta più ETH del
   dovuto;
6. l'attaccante restituisce il flash loan e tiene la differenza.

Il pump serve solo a gonfiare il prezzo letto dall'oracolo: la parte grossa del
guadagno viene dagli sUSD comprati a prezzo giusto e valutati a quel prezzo gonfiato.
Per misurare il contributo di ciascuna parte, i test confrontano questa strategia con
quella a un solo mercato (solo pump).

## Struttura

| Contratto (`src/`) | Ruolo |
|---|---|
| `MockToken` | ERC20 con mint libero, simula ETH e sUSD |
| `SimpleAMM` | pool `x·y = k`: prezzo spot e accumulatore di prezzo per il TWAP |
| `FixedPriceMarket` | secondo mercato: vende sUSD a prezzo fisso, l'oracolo non lo legge |
| `IPriceOracle` → `PriceOracleSpot` / `PriceOracleTWAP` | oracolo spot (vulnerabile) e TWAP (mitigazione) |
| `VulnerableLending` | presta ETH contro sUSD, valutato tramite l'oracolo iniettato |
| `FlashLender` / `IFlashBorrower` | flash loan con verifica del rimborso |
| `AttackerFair` | l'attacco: divide il flash loan tra pump e acquisto a prezzo giusto |
| `Attacker` | caso di confronto a un solo mercato: tutto il flash loan nel pump |

Il lending dipende dall'interfaccia `IPriceOracle`: lo stesso attacco viene eseguito
cambiando solo l'oracolo.

## Risultati

Pool `1000 ETH / 300 000 sUSD`, collateral factor `cf = 0.667`.

**L'attacco:**

| Scenario | Esito |
|---|---|
| Pump 900 ETH + 1 000 ETH a prezzo giusto, oracolo spot | **+1 648,44 ETH** all'attaccante |
| Pump 300 ETH + 1 000 ETH a prezzo giusto, oracolo spot | **+87,36 ETH** |
| Pump 900 ETH + 1 000 ETH a prezzo giusto, oracolo TWAP | **revert**: nessuno perde nulla |

**Confronto con un solo mercato (solo pump):**

| Scenario | Esito |
|---|---|
| Solo pump 900 ETH, oracolo spot | **+240,56 ETH** all'attaccante, **−666,88 ETH** al lending |
| Solo pump 300 ETH, oracolo spot | **revert**: il prestito non basta a restituire il flash loan |
| Solo pump 900 ETH, oracolo TWAP | **revert** |

**Condizione di profitto.** Con `dx` ETH nel pump, `X` riserva ETH del pool e `F` ETH
spesi a prezzo giusto:

```
profitto = dx · [ cf·(1 + dx/X) − 1 ]  +  F · [ cf·(1 + dx/X)² − 1 ]
              parte pump                    parte a prezzo giusto
```

Il pump moltiplica il prezzo di sUSD per `(1 + dx/X)²`, quindi la parte a prezzo giusto
rende appena il pump alza il prezzo più di `1/cf` volte: con `cf = 0.667` basta
`dx/X > 0.22`. Con un solo mercato (`F = 0`) serve invece `dx/X > (1 − cf)/cf ≈ 0.5`.
Il parameter sweep (`test/Sweep.t.sol`, 5 valori di `cf` × 8 rapporti `dx/X`) misura la
parte di pump direttamente sui contratti: ogni curva di `analysis/sweep_profit.png`
attraversa lo zero esattamente alla soglia teorica.

**Mitigazione.** Il TWAP è una media dei prezzi pesata sul tempo. Dentro la transazione
dell'attacco il tempo non avanza, quindi il prezzo gonfiato pesa zero: **tutto** il
collaterale, anche quello comprato a prezzo giusto, viene valutato al prezzo vero, e
l'attaccante non riesce a restituire il flash loan.

**Dati reali.** Nel dataset SoK (199 incidenti, luglio 2018 – novembre 2022) la
manipolazione di oracoli on-chain conta **29 incidenti (14,6%)** e **597,2 M USD** di
danni: è la seconda causa più frequente (`analysis/dataset_top_causes.png`,
`analysis/dataset_per_year.png`).

## Come si esegue

Requisiti: [Foundry](https://getfoundry.sh/); Python 3 con `matplotlib` per i grafici.

Le librerie (`forge-std`, OpenZeppelin) sono sottomoduli git: clonare con
`git clone --recurse-submodules <url>`, oppure dopo il clone eseguire
`git submodule update --init --recursive`.

```bash
forge test -vv                                      # tutti i test
forge test --match-path test/AttackFair.t.sol -vv   # l'attacco, con i numeri e il TWAP
forge test --match-path test/Attack.t.sol -vv       # confronto: solo pump
forge test --match-path test/AttackTWAP.t.sol -vv   # confronto: solo pump con TWAP
forge test --match-test test_Sweep                  # rigenera analysis/sweep_results.csv
python3 analysis/sweep_plot.py                      # grafico dello sweep
python3 analysis/dataset_stats.py                   # statistiche e grafici del dataset
```

## Limiti

- Fee e gas sono ignorati
- Il TWAP usa la finestra "dall'ultimo aggiornamento a ora", non una finestra mobile di
  lunghezza fissa

## Riferimenti

- K. Qin, L. Zhou, B. Livshits, A. Gervais, *Attacking the DeFi Ecosystem with Flash
  Loans for Fun and Profit*, Financial Cryptography 2021.
  [arXiv:2003.03810](https://arxiv.org/abs/2003.03810)
- L. Zhou et al., *SoK: Decentralized Finance (DeFi) Attacks*, IEEE Symposium on
  Security and Privacy 2023. Il file `analysis/data/defi_sok.db` proviene da
  [Research-Imperium/SoKDeFiAttacks](https://github.com/Research-Imperium/SoKDeFiAttacks)
  ed è distribuito con licenza **CC BY-NC**: è incluso qui solo per scopi didattici,
  non commerciali.
