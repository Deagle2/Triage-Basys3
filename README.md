# Basys3-Triage - [ReadME WIP]

## Abstract
Emergency department triage is one of the most time-critical tasks in modern healthcare. Traditional manual triage
systems introduce delays and rely on periodic nursing checks, which can miss early deterioration in busy departments, a
problem that hits hardest in a country like India, where the physician-to-patient ratio sits at roughly 0.7 per 1,000 people
and emergency wards regularly run at two to three times their intended capacity. Cloud-based AI tools seem like an
obvious fix, but they bring their own headaches: round-trip latency of 150-300 ms, a hard dependency on internet
connectivity that simply does not exist in most Indian ambulances, and real privacy exposure every time a patient's
biometrics leave the building.
This project takes a different approach. We built a complete, self-contained triage classifier directly on a Xilinx Artix-7
FPGA (Digilent Basys3), processing Heart Rate, Body Temperature, and SpO2 through a trained 3→16→3 Multi-Layer
Perceptron and classifying patients as GREEN (routine), YELLOW (urgent), or RED (critical).
The system employs a dual-inference strategy: the MLP handles the nuanced, non-linear pattern recognition that
threshold rules miss, while a parallel rule-based module independently monitors each vital against clinical thresholds
and encodes exactly which signal triggered the alert into a UART diagnostic packet. A model with 115 parameters using Q8.8 fixed-point arithmetic
synthesised into LUT logic, produces one classification per 6 clock cycles and consumes 180 mW total. The neural
network was trained on 5,909 real clinical records (augmented to 12,930 with SMOTE), achieving 94.9–98.0% validation


## Schematic
*Fig 1. Top Module (Vivado 2018.1)*
---
<img width="1510" height="665" alt="image" src="https://github.com/user-attachments/assets/16815efb-52ef-4a20-95d3-43ff9466207f" />


*Fig 2. MLP (3-16-3) (Vivado 2025.1)*
---
<img width="1256" height="738" alt="image" src="https://github.com/user-attachments/assets/344c5528-b7c8-408a-b572-5597444796dd" />

---


