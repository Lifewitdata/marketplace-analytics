"""In-process notebook executor: runs code cells top-to-bottom, captures stdout,
embeds display(Image(path)) as base64 PNG outputs. No kernel needed."""
import base64
import io
import json
import re
import traceback
from contextlib import redirect_stdout

NB = "Wanderly_Marketplace_Analytics.ipynb"

nb = json.load(open(NB))
ns = {}

class FakeImage:
    def __init__(self, path):
        self.path = path

def fake_display(obj, *a, **k):
    if isinstance(obj, FakeImage):
        raise _Embed(obj.path)
    print(obj)

class _Embed(Exception):
    def __init__(self, path):
        self.path = path

ns["display"] = fake_display
ns["Image"] = FakeImage

# pandas Styler prints as repr; fine. matplotlib Agg already set in analysis, but
# notebook cells don't plot directly (they display pre-made PNGs), so no backend worry.
import matplotlib
matplotlib.use("Agg")

# --- env stubs (this VM lacks IPython/jinja2; the real notebook runs in VS Code) ---
import pandas as pd

class _Styler:
    """Minimal stand-in for pandas Styler: chains calls, renders as plain table."""
    def __init__(self, df):
        self.df = df
    def __getattr__(self, name):
        def _m(*a, **k):
            return self
        return _m
    def __repr__(self):
        return self.df.to_string()

pd.DataFrame.style = property(lambda self: _Styler(self))

errors = 0
for i, cell in enumerate(nb["cells"]):
    if cell["cell_type"] != "code":
        continue
    src = "".join(cell["source"])
    # strip the IPython import (stubbed in ns); keep everything else
    src = src.replace("from IPython.display import Image, display", "")
    # rewrite display(Image("...")) so we can capture the path
    buf = io.StringIO()
    outputs = []
    try:
        with redirect_stdout(buf):
            try:
                exec(compile(src, f"<cell {i}>", "exec"), ns)
            except _Embed as e:
                data = base64.b64encode(open(e.path, "rb").read()).decode()
                outputs.append({
                    "output_type": "display_data",
                    "data": {"image/png": data, "text/plain": [f"<Image {e.path}>"]},
                    "metadata": {},
                })
        # capture any matplotlib figures the cell created
        import matplotlib.pyplot as plt
        for num in plt.get_fignums():
            fig = plt.figure(num)
            fbuf = io.BytesIO()
            fig.savefig(fbuf, format="png", bbox_inches="tight")
            data = base64.b64encode(fbuf.getvalue()).decode()
            outputs.append({
                "output_type": "display_data",
                "data": {"image/png": data, "text/plain": ["<matplotlib figure>"]},
                "metadata": {},
            })
        plt.close("all")
    except Exception:
        errors += 1
        outputs.append({
            "output_type": "error",
            "ename": "Exception",
            "evalue": traceback.format_exc(limit=3),
            "traceback": [],
        })
    text = buf.getvalue()
    if text:
        outputs.insert(0, {"output_type": "stream", "name": "stdout", "text": text})
    cell["outputs"] = outputs
    cell["execution_count"] = i + 1

json.dump(nb, open(NB, "w"), indent=1)
print(f"executed {NB}: {len(nb['cells'])} cells, {errors} errors")
