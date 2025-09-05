import json
from os import getenv
from pathlib import Path

from flask import Flask
from flask import render_template


app = Flask(__name__)

DATA_DIR = Path(getenv("RISTEYS_DRUGS_DATA"))


# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ DATA

with open(DATA_DIR / "atc_groupings.jsonl") as fd:
    lines = [json.loads(ll) for ll in fd.readlines()]
    lines.sort(key=lambda dd: dd["phenotype"])

    ATC_GROUPINGS = {}
    for dd in lines:
        phenocode = dd.pop("phenocode")
        ATC_GROUPINGS[phenocode] = dd


data = {}
for datafile in (DATA_DIR / 'output/').glob('*/*.json'):
    phenocode = datafile.parent.stem
    stat = datafile.stem

    gg = data.get(phenocode, {})

    with open(datafile) as fd:
        gg[stat] = fd.read()

    data[phenocode] = gg


# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ SERVER

@app.route("/")
def home():
    return render_template("home.html", groupings=ATC_GROUPINGS)


@app.route("/pheno/<phenoid>")
def pheno(phenoid=None):
    gg = ATC_GROUPINGS.get(phenoid)

    if not gg:
        return f"Not found: {phenoid}\n", 404

    else:
        return render_template("pheno.html", phenoid=phenoid, gg=gg, data=data[phenoid])
