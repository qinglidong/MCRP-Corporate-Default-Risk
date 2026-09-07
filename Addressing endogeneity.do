/********************************************************************
  0. Basic setup
********************************************************************/

clear all
set more off

* Set project path
global root "YOUR_LOCAL_PROJECT_PATH"
global data "$root"
global out  "$root/empirical_output"

capture mkdir "$out"

cd "$root"


/********************************************************************
  1. Install auxiliary packages
     estout: export regression tables
     ebalance: entropy balancing
     psmatch2: propensity score matching and balance plots
     coefplot: event-study figure
********************************************************************/

capture which esttab
if _rc {
    ssc install estout, replace
}

capture which ebalance
if _rc {
    ssc install ebalance, replace
}

capture which psmatch2
if _rc {
    ssc install psmatch2, replace
}

capture which coefplot
if _rc {
    ssc install coefplot, replace
}


/********************************************************************
  2. Import original data
********************************************************************/

import excel "$data/原始数据.xlsx", firstrow clear

describe


/*************************************************************
  3. Harmonize key variable names
     If the data already contains DD and MCRP, nothing changes.
     If the old names KMV and MCAI still exist, rename them.
*************************************************************/

capture confirm variable DD
if _rc {
    capture confirm variable KMV
    if _rc {
        display as error "Neither DD nor KMV exists. Please check the dependent variable name."
        exit 111
    }
    rename KMV DD
}

capture confirm variable MCRP
if _rc {
    capture confirm variable MCAI
    if _rc {
        display as error "Neither MCRP nor MCAI exists. Please check the independent variable name."
        exit 111
    }
    rename MCAI MCRP
}

label var DD   "Distance to default"
label var MCRP "Managerial climate risk perception"


/********************************************************************
  4. Construct correct firm identifier
     code is unique, but code is a firm-year identifier.
     It should not be used as panel id.
     The structure is:
         code = firm_id * 10000 + year
********************************************************************/

* Ensure code and year are numeric
capture confirm numeric variable code
if _rc {
    destring code, replace ignore(" ")
}

capture confirm numeric variable year
if _rc {
    destring year, replace ignore(" ")
}

* Check code uniqueness
isid code

* Reconstruct firm_id from code and year
capture drop firm_id firm_id_raw firm_id_check
gen double firm_id_raw = (code - year) / 10000
gen double firm_id_check = firm_id_raw - floor(firm_id_raw)

summ firm_id_check

* The following assertion should pass if code is correctly structured
assert abs(firm_id_check) < 1e-8

gen long firm_id = floor(firm_id_raw)

* If original id is non-missing, verify consistency
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

label var firm_id "Firm identifier reconstructed from code"
label var ind_id  "Industry identifier"

* Check panel uniqueness
isid firm_id year

* Declare panel
xtset firm_id year


/********************************************************************
  5. Define controls
********************************************************************/

global controls Size Lev ROA Fixed Growth ListAge Dual Top1 Cashflow Inv

summ DD MCRP IC WW $controls


/********************************************************************
  6. Generate lagged MCRP and policy-shock variables
********************************************************************/

capture drop L1_MCRP L2_MCRP PostDual PostDual2020
capture drop L1MCRP_PostDual L1MCRP_PostDual2020

gen L1_MCRP = L1.MCRP
gen L2_MCRP = L2.MCRP

label var L1_MCRP "Lagged MCRP"
label var L2_MCRP "Two-year lagged MCRP"

* Main post-shock definition:
* China announced the dual-carbon targets in September 2020.
* Main test uses 2021 and after as post-shock period.
gen PostDual = (year >= 2021)
label var PostDual "Post dual-carbon announcement"

* Sensitivity definition:
* Includes 2020 as the post-shock year.
gen PostDual2020 = (year >= 2020)
label var PostDual2020 "Post dual-carbon announcement, including 2020"

gen L1MCRP_PostDual = L1_MCRP * PostDual
gen L1MCRP_PostDual2020 = L1_MCRP * PostDual2020

label var L1MCRP_PostDual     "L.MCRP x PostDual"
label var L1MCRP_PostDual2020 "L.MCRP x PostDual2020"


/********************************************************************
  7. Table 8: Dual-carbon policy shock and MCRP-DD relation
********************************************************************/

eststo clear

* Column (1): Baseline with lagged MCRP, industry and year fixed effects
reg DD L1_MCRP $controls i.year i.ind_id, vce(cluster firm_id)
eststo T8_1

* Column (2): Shock interaction, industry and year fixed effects
reg DD L1_MCRP L1MCRP_PostDual $controls i.year i.ind_id, vce(cluster firm_id)
eststo T8_2

* Column (3): Shock interaction, firm and year fixed effects
xtreg DD L1_MCRP L1MCRP_PostDual $controls i.year, fe vce(cluster firm_id)
eststo T8_3

* Column (4): Sensitivity test, post-shock defined as 2020 and after
xtreg DD L1_MCRP L1MCRP_PostDual2020 $controls i.year, fe vce(cluster firm_id)
eststo T8_4

esttab T8_1 T8_2 T8_3 T8_4 using "$out/Table8_DualCarbonShock.rtf", ///
    replace b(%9.3f) se(%9.3f) ///
    star(* 0.10 ** 0.05 *** 0.01) ///
    keep(L1_MCRP L1MCRP_PostDual L1MCRP_PostDual2020 ///
         Size Lev ROA Fixed Growth ListAge Dual Top1 Cashflow Inv) ///
    order(L1_MCRP L1MCRP_PostDual L1MCRP_PostDual2020 ///
          Size Lev ROA Fixed Growth ListAge Dual Top1 Cashflow Inv) ///
    stats(N, labels("Observations") fmt(%9.0f)) ///
    mtitles("Baseline" "PostDual x L.MCRP" "Firm FE" "PostDual2020") ///
    title("Table 8. Dual-Carbon Policy Shock and the MCRP-DD Relation") ///
    addnotes("The dependent variable is DD, the KMV-based distance to default.", ///
             "L1_MCRP denotes one-year lagged managerial climate risk perception.", ///
             "PostDual equals one for 2021 and after. PostDual2020 equals one for 2020 and after.", ///
             "Columns (1)-(2) include industry and year fixed effects.", ///
             "Columns (3)-(4) include firm and year fixed effects.", ///
             "Standard errors clustered at the firm level are reported in parentheses.")


/********************************************************************
  8. Construct treatment group using pre-shock MCRP
     Pre-shock period: 2016-2019
     HighMCRP = 1 if firm is in the top tercile of pre-shock MCRP
                within its industry
********************************************************************/

preserve

keep if inrange(year, 2016, 2019)

collapse (mean) pre_MCRP=MCRP ///
         (first) ind_id, by(firm_id)

drop if missing(pre_MCRP)

gen pre_tercile = .

levelsof ind_id, local(indlist)

foreach j of local indlist {
    quietly count if ind_id == `j' & !missing(pre_MCRP)

    if r(N) >= 3 {
        capture drop tmp_tercile
        xtile tmp_tercile = pre_MCRP if ind_id == `j', nq(3)
        replace pre_tercile = tmp_tercile if ind_id == `j'
        drop tmp_tercile
    }
}

gen HighMCRP = (pre_tercile == 3)
replace HighMCRP = . if missing(pre_tercile)

label var HighMCRP "High pre-shock MCRP firm"

keep firm_id HighMCRP pre_MCRP pre_tercile
tempfile treatment
save `treatment', replace

restore

merge m:1 firm_id using `treatment', keep(master match) nogen

capture drop DID_HighMCRP
gen DID_HighMCRP = HighMCRP * PostDual
label var DID_HighMCRP "High pre-shock MCRP x PostDual"

tab HighMCRP
tab HighMCRP year


/********************************************************************
  9. Table 9 Column (1): Unweighted DID
********************************************************************/

eststo clear

xtreg DD DID_HighMCRP $controls i.year if !missing(HighMCRP), ///
    fe vce(cluster firm_id)

eststo T9_1


/********************************************************************
  10. Entropy balancing based on pre-shock firm characteristics
********************************************************************/

preserve

keep if inrange(year, 2016, 2019)

collapse ///
    (mean) DD Size Lev ROA Fixed Growth ListAge Dual Top1 Cashflow Inv IC WW ///
    (first) HighMCRP, by(firm_id)

drop if missing(HighMCRP)

* Drop missing balancing variables
drop if missing(DD, Size, Lev, ROA, Fixed, Growth, ListAge, Dual, Top1, Cashflow, Inv, IC, WW)

* Entropy balancing
capture drop ebal_w
ebalance HighMCRP DD Size Lev ROA Fixed Growth ListAge Dual Top1 Cashflow Inv IC WW, ///
    targets(1) generate(ebal_w)

* In some ebalance versions, treated units do not receive generated weights.
* Set treated firms' weights to 1.
replace ebal_w = 1 if HighMCRP == 1 & missing(ebal_w)

keep firm_id ebal_w
tempfile ebal_weights
save `ebal_weights', replace

restore

merge m:1 firm_id using `ebal_weights', keep(master match) nogen


/********************************************************************
  11. Table 9 Column (2): Entropy-balanced DID
********************************************************************/

xtreg DD DID_HighMCRP $controls i.year [aw=ebal_w] if !missing(ebal_w), ///
    fe vce(cluster firm_id)

eststo T9_2


/********************************************************************
  12. Appendix Table A1: Entropy-balancing covariate balance
********************************************************************/

preserve

keep if inrange(year, 2016, 2019)

collapse ///
    (mean) DD Size Lev ROA Fixed Growth ListAge Dual Top1 Cashflow Inv IC WW ///
    (first) HighMCRP ebal_w, by(firm_id)

drop if missing(HighMCRP)
drop if missing(DD, Size, Lev, ROA, Fixed, Growth, ListAge, Dual, Top1, Cashflow, Inv, IC, WW)

local balvars DD Size Lev ROA Fixed Growth ListAge Dual Top1 Cashflow Inv IC WW

tempfile balance
postfile bal str20 Variable ///
    double TreatedMean ControlMean BeforeDiff ControlMean_EB AfterDiff ///
    using `balance', replace

foreach v of local balvars {

    quietly summarize `v' if HighMCRP == 1
    local mt = r(mean)

    quietly summarize `v' if HighMCRP == 0
    local mc = r(mean)

    quietly summarize `v' [aw=ebal_w] if HighMCRP == 0
    local mce = r(mean)

    post bal ("`v'") (`mt') (`mc') (`mt' - `mc') (`mce') (`mt' - `mce')
}

postclose bal

use `balance', clear

export excel using "$out/Appendix_Table_A1_Entropy_Balance.xlsx", ///
    firstrow(variables) replace

restore


/********************************************************************
  13. PSM based on pre-shock HighMCRP
********************************************************************/

preserve

keep if inrange(year, 2016, 2019)

collapse ///
    (mean) DD Size Lev ROA Fixed Growth ListAge Dual Top1 Cashflow Inv IC WW ///
    (first) HighMCRP, by(firm_id)

drop if missing(HighMCRP)
drop if missing(DD, Size, Lev, ROA, Fixed, Growth, ListAge, Dual, Top1, Cashflow, Inv, IC, WW)

psmatch2 HighMCRP Size Lev ROA Fixed Growth ListAge Dual Top1 Cashflow Inv IC WW DD, ///
    logit neighbor(1) caliper(0.05) common noreplacement

* PSM balance graph
pstest Size Lev ROA Fixed Growth ListAge Dual Top1 Cashflow Inv IC WW DD, both graph
graph export "$out/Appendix_Figure_A2_PSM_Balance.png", replace width(2400)

gen psm_keep = (_support == 1 & _weight < .)
gen psm_w = _weight

* Treated units on common support may have missing _weight in some psmatch2 versions.
replace psm_w = 1 if HighMCRP == 1 & _support == 1 & missing(psm_w)

keep firm_id psm_keep psm_w
tempfile psm_weights
save `psm_weights', replace

restore

merge m:1 firm_id using `psm_weights', keep(master match) nogen


/********************************************************************
  14. Table 9 Column (3): PSM-matched DID
********************************************************************/

xtreg DD DID_HighMCRP $controls i.year [aw=psm_w] if psm_keep == 1, ///
    fe vce(cluster firm_id)

eststo T9_3


/********************************************************************
  15. Export Table 9
********************************************************************/

esttab T9_1 T9_2 T9_3 using "$out/Table9_PreShockHighMCRP_DID.rtf", ///
    replace b(%9.3f) se(%9.3f) ///
    star(* 0.10 ** 0.05 *** 0.01) ///
    keep(DID_HighMCRP Size Lev ROA Fixed Growth ListAge Dual Top1 Cashflow Inv) ///
    order(DID_HighMCRP Size Lev ROA Fixed Growth ListAge Dual Top1 Cashflow Inv) ///
    stats(N, labels("Observations") fmt(%9.0f)) ///
    mtitles("Unweighted DID" "Entropy-balanced DID" "PSM-matched DID") ///
    title("Table 9. DID Based on Pre-Shock High-MCRP Firms") ///
    addnotes("The dependent variable is DD, the KMV-based distance to default.", ///
             "HighMCRP equals one for firms in the top tercile of pre-shock MCRP within industry.", ///
             "PostDual equals one for 2021 and after.", ///
             "All regressions include firm and year fixed effects.", ///
             "Standard errors clustered at the firm level are reported in parentheses.")


/********************************************************************
  16. Dynamic DID / event-study figure
      This is useful as an appendix figure.
      Omitted year: 2019
********************************************************************/

capture drop rel_year Event_m4 Event_m3 Event_m2 Event_0 Event_p1 Event_p2 Event_p3 Event_p4 Event_p5

gen rel_year = year - 2020

gen Event_m4 = HighMCRP * (rel_year <= -4)
gen Event_m3 = HighMCRP * (rel_year == -3)
gen Event_m2 = HighMCRP * (rel_year == -2)
gen Event_0  = HighMCRP * (rel_year == 0)
gen Event_p1 = HighMCRP * (rel_year == 1)
gen Event_p2 = HighMCRP * (rel_year == 2)
gen Event_p3 = HighMCRP * (rel_year == 3)
gen Event_p4 = HighMCRP * (rel_year == 4)
gen Event_p5 = HighMCRP * (rel_year >= 5)

label var Event_m4 "2016 or earlier"
label var Event_m3 "2017"
label var Event_m2 "2018"
label var Event_0  "2020"
label var Event_p1 "2021"
label var Event_p2 "2022"
label var Event_p3 "2023"
label var Event_p4 "2024"
label var Event_p5 "2025 or later"

xtreg DD Event_m4 Event_m3 Event_m2 Event_0 Event_p1 Event_p2 Event_p3 Event_p4 Event_p5 ///
    $controls i.year if !missing(HighMCRP), fe vce(cluster firm_id)

eststo EventStudy

coefplot EventStudy, ///
    keep(Event_m4 Event_m3 Event_m2 Event_0 Event_p1 Event_p2 Event_p3 Event_p4 Event_p5) ///
    vertical ///
    yline(0, lpattern(dash)) ///
    ciopts(recast(rcap)) ///
    title("Dynamic Effect Around the Dual-Carbon Announcement") ///
    ytitle("Coefficient estimate") ///
    xtitle("Event year relative to 2020") ///
    note("Omitted year: 2019")

graph export "$out/Appendix_Figure_A1_Dynamic_DID.png", replace width(2400)


/********************************************************************
  17. Additional lag-based identification check
      This is supplementary, not a formal IV test.
********************************************************************/

eststo clear

reg DD L2_MCRP $controls i.year i.ind_id, vce(cluster firm_id)
eststo LAG_1

xtreg DD L2_MCRP $controls i.year, fe vce(cluster firm_id)
eststo LAG_2

esttab LAG_1 LAG_2 using "$out/Appendix_Table_A2_LagBased_Check.rtf", ///
    replace b(%9.3f) se(%9.3f) ///
    star(* 0.10 ** 0.05 *** 0.01) ///
    keep(L2_MCRP Size Lev ROA Fixed Growth ListAge Dual Top1 Cashflow Inv) ///
    order(L2_MCRP Size Lev ROA Fixed Growth ListAge Dual Top1 Cashflow Inv) ///
    stats(N, labels("Observations") fmt(%9.0f)) ///
    mtitles("Industry-Year FE" "Firm-Year FE") ///
    title("Appendix Table A2. Additional Lag-Based Identification Check") ///
    addnotes("The dependent variable is DD, the KMV-based distance to default.", ///
             "L2_MCRP denotes two-year lagged managerial climate risk perception.", ///
             "This test is reported as an additional lag-based check rather than a formal IV test.", ///
             "Standard errors clustered at the firm level are reported in parentheses.")


/********************************************************************
  18. Save processed data
********************************************************************/

save "$out/processed_panel_section4_2.dta", replace

display "Section 4.2 endogeneity analysis completed."
display "Outputs saved in: $out"
