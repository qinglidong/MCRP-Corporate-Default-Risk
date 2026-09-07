# MCRP-Corporate-Default-Risk

Replication code and documentation for the paper:

**Managerial Climate Risk Perception and Corporate Default Risk: Textual Evidence from Chinese Listed Firms**

## Overview

This repository contains the author-generated code and documentation used to construct the Managerial Climate Risk Perception (MCRP) measure and reproduce the empirical analyses reported in the paper.

The study uses Chinese A-share listed firms from 2016 to 2025. MCRP is constructed from MD&A disclosures using climate-risk keyword screening, LLM-assisted annotation, manual verification, and FinBERT-based semantic classification. Corporate default risk is measured using KMV-based distance to default.

## Data availability

The study uses third-party licensed data from:

- CNRDS: annual reports and MD&A texts
- CSMAR: financial, governance, managerial, media, and stock-market data
- DIB: internal control index

These databases are subject to licensing restrictions and therefore cannot be redistributed through this repository.

Researchers can obtain the same data directly from the respective databases under their standard access conditions. The authors had no special access privileges.

## Code availability

All author-generated code necessary to reproduce the MCRP construction and empirical analyses is provided in this repository.

API credentials and other sensitive authentication information are not included. Users must provide their own API credentials where required.

## Software

Main software used:

- Python
- PyTorch
- Transformers
- Stata

## Citation

Citation information will be added upon publication.

## License

The author-generated code in this repository is released under the MIT License.
