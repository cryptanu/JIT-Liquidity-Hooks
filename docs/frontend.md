# Frontend

The Launch Console lives in `/frontend` as a dependency-free static app.

Capabilities:
- configure launch parameters
- simulate deploy + pool initialization
- replay baseline vs JIT launch swaps
- visualize slippage delta and phase transitions

Run locally:
```bash
python3 -m http.server 4173 --directory frontend
```
Then open `http://localhost:4173`.
