import sys
from pathlib import Path

_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(_ROOT / "vendor"))
sys.path.insert(0, str(_ROOT / "src"))
