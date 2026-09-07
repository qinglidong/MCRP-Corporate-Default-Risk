# MCRP-Corporate-Default-Risk

Replication materials for the paper:

**Managerial Climate Risk Perception and Corporate Default Risk: Textual Evidence from Chinese Listed Firms**

## Overview

This repository provides the author-generated code and documentation associated with the study of the relation between Managerial Climate Risk Perception (MCRP) and corporate default risk among Chinese A-share listed firms from 2016 to 2025.

MCRP is constructed from the Management Discussion and Analysis (MD&A) sections of annual reports through a multi-stage textual analysis procedure combining:

1. climate-risk keyword screening;
2. large-language-model-assisted sentence annotation;
3. manual verification of preliminary labels;
4. FinBERT-based three-class semantic classification; and
5. firm-year aggregation of sentence-level predicted probabilities.

Corporate default risk is measured primarily using the KMV-based distance to default (DD), where a larger value indicates lower default risk.

The empirical analyses include baseline regressions, robustness tests, policy-shock analyses, matching and balancing procedures, instrumental-variable estimation, cross-sectional analyses, and moderating-effect tests.

---

## Repository contents

The main files currently included in the repository are:

| File | Purpose |
| --- | --- |
| `MCRP.txt` | Text-processing, LLM-assisted annotation, FinBERT fine-tuning, sentence-level prediction, and MCRP construction workflow |
| `stata code of empirical part.txt` | Main Stata workflow for the empirical analysis |
| `Robustness.do` | Robustness tests using alternative dependent variables, alternative MCRP measures, fixed-effect specifications, and alternative samples |
| `Addressing endogeneity.do` | Dual-carbon policy-shock and related endogeneity analyses |
| `IV test.do` | Two-stage least squares analysis using lagged leave-one-out industry peer MCRP as the instrument |
| `managerial_controls_merge_analysis.do` | Additional robustness analysis incorporating CEO-level managerial controls |
| `Media attention - Heterogeneity analysis.do` | Cross-sectional analysis based on high versus low media attention |
| `MCRP1 raw data.xlsx` | Author-generated alternative word-frequency-based MCRP measure |
| `MCRP2&MCRP3.xlsx` | Author-generated semantic components used in alternative MCRP analyses |
| `requirements.txt` | Python package requirements |
| `documentation/data_source_manifest.xlsx` | Data sources, access information, retrieval dates, licensing restrictions, and replication requirements |
| `documentation/variable_dictionary.xlsx` | Definitions and construction information for variables used in the study |

Additional documentation may be added as the replication package is finalized.



## Data sources and availability

The study relies on three licensed third-party databases.

### CNRDS

Annual reports and MD&A texts were obtained from the Chinese Research Data Services Platform (CNRDS):

https://www.cnrds.com/

Data were retrieved by the authors by the end of December 2025.

### CSMAR

Financial statement data, corporate governance variables, stock-market data, CEO characteristics, and media-attention variables were obtained from the China Stock Market & Accounting Research (CSMAR) database:

https://data.csmar.com/

Data were retrieved by the authors by the end of December 2025.

### DIB

Internal control quality was obtained from the DIB Internal Control Index database:

https://www.dibdata.cn/

Data were retrieved by the authors by the end of December 2025.

### Third-party licensing restrictions

The underlying CNRDS, CSMAR, and DIB data are subject to third-party licensing restrictions and are therefore **not redistributed through this repository**.

Researchers seeking to reproduce the study should obtain the corresponding data directly from these databases under their standard access conditions. The authors had no special access privileges.

Information on the specific data sources, variable groups, access conditions, and processing procedures is provided in:

`documentation/data_source_manifest.xlsx`

---

## Replication workflow

A typical replication procedure is as follows.

### Step 1. Obtain the licensed source data

Obtain:

- MD&A annual-report texts from CNRDS;
- financial, governance, market, managerial, and media data from CSMAR;
- internal-control data from DIB.

### Step 2. Construct MCRP

Prepare the MD&A text files and run the MCRP construction workflow.

The procedure includes:

1. MD&A text parsing and sentence segmentation;
2. climate-risk keyword screening;
3. year-stratified sampling of candidate sentences;
4. LLM-assisted preliminary annotation;
5. manual verification of training labels;
6. FinBERT fine-tuning;
7. full-sample sentence classification; and
8. firm-year aggregation.

Users must provide their own valid API credentials for the LLM-assisted annotation stage.

### Step 3. Construct default-risk measures

Construct the KMV-based distance to default and alternative default-risk measures using the required financial and stock-market data.

### Step 4. Merge the firm-year data

Merge textual, financial, governance, market, internal-control, managerial, and media variables using firm identifiers and year.

### Step 5. Run the empirical analyses

The Stata scripts reproduce the main empirical analyses, including:

1. baseline regressions;
2. robustness tests;
3. dual-carbon policy-shock analyses;
4. entropy-balancing and propensity-score-matching analyses;
5. instrumental-variable estimation;
6. cross-sectional analyses; and
7. moderating-effect analyses.

Because the licensed source datasets cannot be redistributed, users must adjust the local working directory and input-file locations before running the scripts.

---

## API credentials

No API keys, passwords, access tokens, or other private authentication credentials are included in this repository.

Users requiring LLM-assisted annotation should provide their own API credentials.

For example, API credentials may be supplied through an environment variable rather than hard-coded in the source file:

```python
import os

ZHIPU_API_KEY = os.getenv("ZHIPU_API_KEY")
