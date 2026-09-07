
/********************************************************************
  0. Basic setup
********************************************************************/

clear all
set more off
set varabbrev off

global root "YOUR_LOCAL_PROJECT_PATH"
global out  "$root/robustness_output"

capture mkdir "$out"
cd "$root"

capture which esttab
if _rc {
    ssc install estout, replace
}


/********************************************************************
  1. Import original data
     File: 原始数据.xlsx
********************************************************************/

import excel "$root/原始数据.xlsx", firstrow clear

* Harmonize core variable names if needed
capture confirm variable DD
if _rc {
    capture confirm variable KMV
    if !_rc {
        rename KMV DD
    }
    else {
        display as error "Neither DD nor KMV exists in 原始数据.xlsx."
        exit 111
    }
}

capture confirm variable MCRP
if _rc {
    capture confirm variable MCAI
    if !_rc {
        rename MCAI MCRP
    }
    else {
        display as error "Neither MCRP nor MCAI exists in 原始数据.xlsx."
        exit 111
    }
}

* Ensure code and year are numeric
capture confirm numeric variable code
if _rc {
    destring code, replace ignore(" ")
}

capture confirm numeric variable year
if _rc {
    destring year, replace ignore(" ")
}

* Construct firm identifier from code
* code = firm_id * 10000 + year
capture drop firm_id firm_id_raw firm_id_check

gen double firm_id_raw = (code - year) / 10000
gen double firm_id_check = firm_id_raw - floor(firm_id_raw)

summ firm_id_check
assert abs(firm_id_check) < 1e-8

gen long firm_id = floor(firm_id_raw)

* Check consistency with original id if available
capture confirm variable id
if !_rc {
    assert firm_id == id if !missing(id)
}

drop firm_id_raw firm_id_check

* Industry fixed-effect identifier
capture drop ind_id

capture confirm numeric variable Ind
if _rc {
    egen ind_id = group(Ind), label
}
else {
    gen ind_id = Ind
}

* Check panel uniqueness
isid firm_id year

* Declare panel
xtset firm_id year

label var DD       "Distance to default"
label var MCRP     "Managerial climate risk perception"
label var firm_id  "Firm identifier"
label var ind_id   "Industry identifier"

tempfile main
save `main', replace


/********************************************************************
  2. Import alternative dependent variables
     File: 合并4（企业债务违约）.dta

     Main robustness variables selected:
        DDBhsh
        DDmerton
        ZScore

     DDKMV is checked but not included in the main robustness table,
     because it is likely very close to the baseline DD.
********************************************************************/

use "$root/合并4（企业债务违约）.dta", clear

* Harmonize firm identifier
capture confirm variable Stkcd
if !_rc {
    capture confirm numeric variable Stkcd
    if _rc {
        destring Stkcd, replace ignore(" ")
    }
    rename Stkcd firm_id
}
else {
    capture confirm variable stkcd
    if !_rc {
        capture confirm numeric variable stkcd
        if _rc {
            destring stkcd, replace ignore(" ")
        }
        rename stkcd firm_id
    }
    else {
        display as error "Neither Stkcd nor stkcd exists in 合并4（企业债务违约）.dta."
        exit 111
    }
}

capture confirm numeric variable year
if _rc {
    destring year, replace ignore(" ")
}

* Keep useful variables
keep firm_id year DD DDBhsh DDmerton DDKMV ZScore EDF OScore RiskCoefficient DownsideRisk Violate

duplicates drop firm_id year, force

tempfile debt_alt
save `debt_alt', replace


/********************************************************************
  3. Import alternative MCRP measure: MCRP1
     File: 词频MCRP1.xlsx

     MCRP1 = total_climate_freq / total_all_word
********************************************************************/

import excel "$root/词频MCRP1.xlsx", firstrow clear

* Expected columns:
* id year total_climate_freq total_all_word MCRP1

capture confirm variable id
if !_rc {
    rename id firm_id
}

capture confirm numeric variable firm_id
if _rc {
    destring firm_id, replace ignore(" ")
}

capture confirm numeric variable year
if _rc {
    destring year, replace ignore(" ")
}

capture confirm numeric variable total_climate_freq
if _rc {
    destring total_climate_freq, replace force
}

capture confirm numeric variable total_all_word
if _rc {
    destring total_all_word, replace force
}

capture confirm numeric variable MCRP1
if _rc {
    destring MCRP1, replace force
}

keep firm_id year total_climate_freq total_all_word MCRP1

duplicates drop firm_id year, force

label var MCRP1 "Climate-risk word frequency"

tempfile mcrp1_alt
save `mcrp1_alt', replace


/********************************************************************
  4. Import alternative MCRP measures: MCRP2 and MCRP3
     File: MCRP2&MCRP3.xlsx

     MCRP2 = maximum negative probability among risk-exposure sentences
     MCRP3 = mean positive probability among risk-prevention sentences

     Note:
        This file contains Chinese headers. To avoid Stata abbreviation
        problems, variables are renamed by column order immediately.
********************************************************************/

import excel "$root/MCRP2&MCRP3.xlsx", firstrow clear

describe

* Rename by fixed column order:
* Column A = id
* Column B = year
* Column C = MCRP2
* Column D = MCRP3
* Column E = annual sentence count

ds
local allvars `r(varlist)'

local v1 : word 1 of `allvars'
local v2 : word 2 of `allvars'
local v3 : word 3 of `allvars'
local v4 : word 4 of `allvars'
local v5 : word 5 of `allvars'

rename `v1' firm_id
rename `v2' year
rename `v3' MCRP2
rename `v4' MCRP3
rename `v5' annual_sentence_count

foreach v in firm_id year MCRP2 MCRP3 annual_sentence_count {
    capture confirm numeric variable `v'
    if _rc {
        destring `v', replace force
    }
}

label var MCRP2 "Maximum negative probability of risk-exposure sentences"
label var MCRP3 "Mean positive probability of risk-prevention sentences"
label var annual_sentence_count "Annual climate-risk sentence count"

keep firm_id year MCRP2 MCRP3 annual_sentence_count

duplicates drop firm_id year, force

tempfile mcrp23_alt
save `mcrp23_alt', replace


/*************************************************************
  5. Merge all data
*************************************************************/

use `main', clear

merge 1:1 firm_id year using `debt_alt', nogen keep(master match)
merge 1:1 firm_id year using `mcrp1_alt', nogen keep(master match)
merge 1:1 firm_id year using `mcrp23_alt', nogen keep(master match)

* Following the text-construction logic, missing text-based measures
* can be treated as zero when no relevant text is identified.
foreach v in MCRP1 MCRP2 MCRP3 total_climate_freq total_all_word annual_sentence_count {
    capture confirm variable `v'
    if !_rc {
        replace `v' = 0 if missing(`v')
    }
}

* Construct industry-year fixed effect
capture drop ind_year
egen ind_year = group(ind_id year), label

* Declare panel again
xtset firm_id year

save "$out/merged_robustness_data.dta", replace


/********************************************************************
  6. Preliminary diagnostic: whether DDKMV is redundant with DD
     This is diagnostic only. DDKMV is not included in the main table.
********************************************************************/

capture confirm variable DDKMV
if !_rc {
    capture drop diff_DD_DDKMV
    gen diff_DD_DDKMV = DD - DDKMV

    summarize DD DDKMV diff_DD_DDKMV
    correlate DD DDKMV
    count if abs(diff_DD_DDKMV) > 1e-8 & !missing(diff_DD_DDKMV)

    display as text "Diagnostic completed: If DD and DDKMV are nearly identical, DDKMV should not be reported as a main robustness test."
}


/********************************************************************
  7. Define controls and standardize alternative MCRP measures
********************************************************************/

global controls Size Lev ROA Fixed Growth ListAge Dual Top1 Cashflow Inv

* Standardize alternative MCRP measures to avoid scale-driven coefficients
foreach v in MCRP1 MCRP2 MCRP3 {
    capture drop z_`v'
    egen z_`v' = std(`v')
    label var z_`v' "`v' standardized"
}

label var DD        "Distance to default"
label var DDBhsh    "Alternative distance to default: DDBhsh"
label var DDmerton  "Alternative distance to default: DDmerton"
label var ZScore    "Altman Z-score"
label var MCRP      "Managerial climate risk perception"
label var z_MCRP1   "MCRP1 standardized"
label var z_MCRP2   "MCRP2 standardized"
label var z_MCRP3   "MCRP3 standardized"


/********************************************************************
  8. Robustness regressions
********************************************************************/

eststo clear


/********************************************************************
  Column (1): Alternative dependent variable: DDBhsh
********************************************************************/

reg DDBhsh MCRP $controls i.year i.ind_id, vce(cluster firm_id)

estadd local DepVar     "DDBhsh"
estadd local CoreVar    "MCRP"
estadd local IndustryFE "Yes"
estadd local FirmFE     "No"
estadd local IndYearFE  "No"
estadd local YearFE     "Yes"
estadd local Sample     "Full"
estadd scalar R2 = e(r2)

eststo R1


/********************************************************************
  Column (2): Alternative dependent variable: DDmerton
********************************************************************/

reg DDmerton MCRP $controls i.year i.ind_id, vce(cluster firm_id)

estadd local DepVar     "DDmerton"
estadd local CoreVar    "MCRP"
estadd local IndustryFE "Yes"
estadd local FirmFE     "No"
estadd local IndYearFE  "No"
estadd local YearFE     "Yes"
estadd local Sample     "Full"
estadd scalar R2 = e(r2)

eststo R2


/********************************************************************
  Column (3): Alternative financial-distress measure: ZScore
********************************************************************/

reg ZScore MCRP $controls i.year i.ind_id, vce(cluster firm_id)

estadd local DepVar     "ZScore"
estadd local CoreVar    "MCRP"
estadd local IndustryFE "Yes"
estadd local FirmFE     "No"
estadd local IndYearFE  "No"
estadd local YearFE     "Yes"
estadd local Sample     "Full"
estadd scalar R2 = e(r2)

eststo R3


/********************************************************************
  Column (4): Alternative MCRP measure: MCRP1 standardized
********************************************************************/

reg DD z_MCRP1 $controls i.year i.ind_id, vce(cluster firm_id)

estadd local DepVar     "DD"
estadd local CoreVar    "MCRP1 std."
estadd local IndustryFE "Yes"
estadd local FirmFE     "No"
estadd local IndYearFE  "No"
estadd local YearFE     "Yes"
estadd local Sample     "Full"
estadd scalar R2 = e(r2)

eststo R4


/********************************************************************
  Column (5): Alternative MCRP measure: MCRP2 standardized
********************************************************************/

reg DD z_MCRP2 $controls i.year i.ind_id, vce(cluster firm_id)

estadd local DepVar     "DD"
estadd local CoreVar    "MCRP2 std."
estadd local IndustryFE "Yes"
estadd local FirmFE     "No"
estadd local IndYearFE  "No"
estadd local YearFE     "Yes"
estadd local Sample     "Full"
estadd scalar R2 = e(r2)

eststo R5


/********************************************************************
  Column (6): Alternative MCRP component: MCRP3 standardized
********************************************************************/

reg DD z_MCRP3 $controls i.year i.ind_id, vce(cluster firm_id)

estadd local DepVar     "DD"
estadd local CoreVar    "MCRP3 std."
estadd local IndustryFE "Yes"
estadd local FirmFE     "No"
estadd local IndYearFE  "No"
estadd local YearFE     "Yes"
estadd local Sample     "Full"
estadd scalar R2 = e(r2)

eststo R6


/********************************************************************
  Column (7): Firm and year fixed effects
********************************************************************/

xtreg DD MCRP $controls i.year, fe vce(cluster firm_id)

estadd local DepVar     "DD"
estadd local CoreVar    "MCRP"
estadd local IndustryFE "No"
estadd local FirmFE     "Yes"
estadd local IndYearFE  "No"
estadd local YearFE     "Yes"
estadd local Sample     "Full"
estadd scalar R2 = e(r2_w)

eststo R7


/********************************************************************
  Column (8): Industry-year fixed effects
********************************************************************/

reg DD MCRP $controls i.ind_year, vce(cluster firm_id)

estadd local DepVar     "DD"
estadd local CoreVar    "MCRP"
estadd local IndustryFE "No"
estadd local FirmFE     "No"
estadd local IndYearFE  "Yes"
estadd local YearFE     "Included"
estadd local Sample     "Full"
estadd scalar R2 = e(r2)

eststo R8


/********************************************************************
  Column (9): Excluding 2020
********************************************************************/

reg DD MCRP $controls i.year i.ind_id if year != 2020, vce(cluster firm_id)

estadd local DepVar     "DD"
estadd local CoreVar    "MCRP"
estadd local IndustryFE "Yes"
estadd local FirmFE     "No"
estadd local IndYearFE  "No"
estadd local YearFE     "Yes"
estadd local Sample     "Excl. 2020"
estadd scalar R2 = e(r2)

eststo R9


/********************************************************************
  Column (10): Excluding 2020–2022
********************************************************************/

reg DD MCRP $controls i.year i.ind_id if !inlist(year, 2020, 2021, 2022), vce(cluster firm_id)

estadd local DepVar     "DD"
estadd local CoreVar    "MCRP"
estadd local IndustryFE "Yes"
estadd local FirmFE     "No"
estadd local IndYearFE  "No"
estadd local YearFE     "Yes"
estadd local Sample     "Excl. 2020-2022"
estadd scalar R2 = e(r2)

eststo R10


/********************************************************************
  9. Export robustness table
     Control variables and constant term are displayed.
********************************************************************/

esttab R1 R2 R3 R4 R5 R6 R7 R8 R9 R10 ///
    using "$out/Table_Robustness_Tests_Revised.rtf", ///
    replace ///
    b(%9.3f) se(%9.3f) ///
    star(* 0.10 ** 0.05 *** 0.01) ///
    nodepvars nonumbers ///
    mtitles("(1) DDBhsh" ///
            "(2) DDmerton" ///
            "(3) ZScore" ///
            "(4) MCRP1" ///
            "(5) MCRP2" ///
            "(6) MCRP3" ///
            "(7) Firm FE" ///
            "(8) Ind-Year FE" ///
            "(9) Excl. 2020" ///
            "(10) Excl. 2020-2022") ///
    keep(MCRP z_MCRP1 z_MCRP2 z_MCRP3 ///
         Size Lev ROA Fixed Growth ListAge Dual Top1 Cashflow Inv _cons) ///
    order(MCRP z_MCRP1 z_MCRP2 z_MCRP3 ///
          Size Lev ROA Fixed Growth ListAge Dual Top1 Cashflow Inv _cons) ///
    varlabels( ///
        MCRP      "MCRP" ///
        z_MCRP1   "MCRP1 (std.)" ///
        z_MCRP2   "MCRP2 (std.)" ///
        z_MCRP3   "MCRP3 (std.)" ///
        Size      "Size" ///
        Lev       "Lev" ///
        ROA       "ROA" ///
        Fixed     "Fixed" ///
        Growth    "Growth" ///
        ListAge   "ListAge" ///
        Dual      "Dual" ///
        Top1      "Top1" ///
        Cashflow  "Cashflow" ///
        Inv       "Inv" ///
        _cons     "Constant" ///
    ) ///
    stats(DepVar CoreVar IndustryFE FirmFE IndYearFE YearFE Sample N R2, ///
        labels("Dependent variable" ///
               "Core variable" ///
               "Industry FE" ///
               "Firm FE" ///
               "Industry-year FE" ///
               "Year FE" ///
               "Sample" ///
               "Observations" ///
               "R-squared") ///
        fmt(%15s %15s %9s %9s %9s %9s %18s %9.0f %9.3f)) ///
    title("Table X. Robustness Tests") ///
    addnotes("Standard errors clustered at the firm level are reported in parentheses.", ///
             "DD, DDBhsh, and DDmerton are distance-to-default measures; larger values indicate lower default risk.", ///
             "ZScore is used as an alternative financial-distress measure; larger values indicate lower distress risk.", ///
             "MCRP1, MCRP2, and MCRP3 are standardized to ease interpretation and avoid scale-driven coefficient magnitudes.", ///
             "MCRP1 is based on climate-risk word frequency.", ///
             "MCRP2 is the exposure-related probability component.", ///
             "MCRP3 is the prevention-related probability component and is used as a component-level validity test rather than a direct substitute for MCRP.", ///
             "DDKMV is not reported because it is conceptually close to the baseline KMV-based DD.", ///
             "For the firm fixed-effect specification, R-squared refers to within R-squared.")


/********************************************************************
  10. Optional appendix check: DDKMV
      Run only as diagnostic/supplementary evidence, not main table.
********************************************************************/

capture confirm variable DDKMV
if !_rc {

    eststo clear

    reg DDKMV MCRP $controls i.year i.ind_id, vce(cluster firm_id)

    estadd local DepVar     "DDKMV"
    estadd local CoreVar    "MCRP"
    estadd local IndustryFE "Yes"
    estadd local YearFE     "Yes"
    estadd scalar R2 = e(r2)

    eststo DDKMV_check

    esttab DDKMV_check using "$out/Appendix_DDKMV_Check.rtf", ///
        replace ///
        b(%9.3f) se(%9.3f) ///
        star(* 0.10 ** 0.05 *** 0.01) ///
        nodepvars nonumbers ///
        mtitles("(1) DDKMV") ///
        keep(MCRP Size Lev ROA Fixed Growth ListAge Dual Top1 Cashflow Inv _cons) ///
        order(MCRP Size Lev ROA Fixed Growth ListAge Dual Top1 Cashflow Inv _cons) ///
        varlabels( ///
            MCRP      "MCRP" ///
            Size      "Size" ///
            Lev       "Lev" ///
            ROA       "ROA" ///
            Fixed     "Fixed" ///
            Growth    "Growth" ///
            ListAge   "ListAge" ///
            Dual      "Dual" ///
            Top1      "Top1" ///
            Cashflow  "Cashflow" ///
            Inv       "Inv" ///
            _cons     "Constant" ///
        ) ///
        stats(DepVar CoreVar IndustryFE YearFE N R2, ///
            labels("Dependent variable" ///
                   "Core variable" ///
                   "Industry FE" ///
                   "Year FE" ///
                   "Observations" ///
                   "R-squared") ///
            fmt(%15s %15s %9s %9s %9.0f %9.3f)) ///
        title("Appendix Table. DDKMV Diagnostic Check") ///
        addnotes("DDKMV is reported only as a diagnostic check because it is conceptually close to the baseline KMV-based DD.", ///
                 "Standard errors clustered at the firm level are reported in parentheses.")
}


/********************************************************************
  11. Optional appendix: risk-increasing measures
      These are not included in the main robustness table because their
      expected coefficients are negative.
********************************************************************/

eststo clear

capture confirm variable EDF
if !_rc {
    reg EDF MCRP $controls i.year i.ind_id, vce(cluster firm_id)
    estadd local DepVar "EDF"
    estadd local ExpectedSign "Negative"
    estadd scalar R2 = e(r2)
    eststo A1
}

capture confirm variable OScore
if !_rc {
    reg OScore MCRP $controls i.year i.ind_id, vce(cluster firm_id)
    estadd local DepVar "OScore"
    estadd local ExpectedSign "Negative"
    estadd scalar R2 = e(r2)
    eststo A2
}

capture confirm variable RiskCoefficient
if !_rc {
    reg RiskCoefficient MCRP $controls i.year i.ind_id, vce(cluster firm_id)
    estadd local DepVar "RiskCoefficient"
    estadd local ExpectedSign "Negative"
    estadd scalar R2 = e(r2)
    eststo A3
}

capture confirm variable DownsideRisk
if !_rc {
    reg DownsideRisk MCRP $controls i.year i.ind_id, vce(cluster firm_id)
    estadd local DepVar "DownsideRisk"
    estadd local ExpectedSign "Negative"
    estadd scalar R2 = e(r2)
    eststo A4
}

capture noisily esttab A1 A2 A3 A4 using "$out/Appendix_RiskIncreasing_Measures.rtf", ///
    replace ///
    b(%9.3f) se(%9.3f) ///
    star(* 0.10 ** 0.05 *** 0.01) ///
    nodepvars nonumbers ///
    mtitles("(1) EDF" "(2) OScore" "(3) RiskCoefficient" "(4) DownsideRisk") ///
    keep(MCRP Size Lev ROA Fixed Growth ListAge Dual Top1 Cashflow Inv _cons) ///
    order(MCRP Size Lev ROA Fixed Growth ListAge Dual Top1 Cashflow Inv _cons) ///
    stats(DepVar ExpectedSign N R2, ///
        labels("Dependent variable" "Expected sign of MCRP" "Observations" "R-squared") ///
        fmt(%15s %10s %9.0f %9.3f)) ///
    title("Appendix Table. Robustness Tests Using Risk-Increasing Measures") ///
    addnotes("These dependent variables are risk-increasing measures; therefore, the expected coefficient on MCRP is negative.", ///
             "Standard errors clustered at the firm level are reported in parentheses.")


/********************************************************************
  12. Save final robustness dataset
********************************************************************/

save "$out/robustness_final_dataset_revised.dta", replace

display "Revised robustness analysis completed."
display "Main robustness table saved to: $out/Table_Robustness_Tests_Revised.rtf"
display "DDKMV appendix check saved to: $out/Appendix_DDKMV_Check.rtf"
display "Risk-increasing appendix table saved to: $out/Appendix_RiskIncreasing_Measures.rtf"
