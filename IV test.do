/**********************************************************************
  2SLS: Instrumental-variable analysis

  Instrument:
  One-year-lagged leave-one-out industry-year mean MCRP

  Main data:
  G:\联合指导\连兰兰合作论文\paper 4\论文+数据+代码\原始数据.xlsx
**********************************************************************/

clear all
set more off
set varabbrev off

global root "G:/联合指导/连兰兰合作论文/paper 4/论文+数据+代码"
global data "$root/原始数据.xlsx"

cd "$root"


/**********************************************************************
  1. Import data
**********************************************************************/

import excel "$data", firstrow clear

* Firm identifier
capture confirm numeric variable id
if _rc destring id, replace ignore(" ")

* Year
capture confirm numeric variable year
if _rc destring year, replace ignore(" ")

* Industry
capture drop ind_id

capture confirm numeric variable Ind
if _rc {
    encode Ind, gen(ind_id)
}
else {
    gen long ind_id = Ind
}

* Check uniqueness
isid id year

* Sample period
keep if inrange(year,2016,2025)

* Declare panel
xtset id year


/**********************************************************************
  2. Baseline controls
**********************************************************************/

global controls ///
    Size Lev ROA Fixed Growth ListAge Dual Top1 Cashflow Inv


/**********************************************************************
  3. Construct leave-one-out industry peer MCRP
**********************************************************************/

* Industry-year number of firms
bysort ind_id year: egen peer_N = count(MCRP)

* Industry-year total MCRP
bysort ind_id year: egen peer_sum_MCRP = total(MCRP)

* Leave-one-out industry-year mean MCRP
gen PeerMCRP = ///
    (peer_sum_MCRP - MCRP) / (peer_N - 1) ///
    if peer_N > 1 & !missing(MCRP)

label var PeerMCRP ///
    "Leave-one-out industry-year peer MCRP"



/**********************************************************************
  4. Lag the peer instrument by one year
**********************************************************************/

* Re-declare panel structure because bysort ind_id year
* changed the current data ordering
sort id year
xtset id year

capture drop L1_PeerMCRP
gen L1_PeerMCRP = L.PeerMCRP

label var L1_PeerMCRP ///
    "Lagged leave-one-out industry peer MCRP"

* Check
summarize PeerMCRP L1_PeerMCRP, detail


/**********************************************************************
  5. Diagnostics
**********************************************************************/

summarize MCRP PeerMCRP L1_PeerMCRP, detail

corr MCRP PeerMCRP L1_PeerMCRP

* Relevant first-stage sample
count if !missing(DD, MCRP, L1_PeerMCRP)

display "IV sample N = " r(N)


/**********************************************************************
  6. First-stage regression
**********************************************************************/

reg MCRP ///
    L1_PeerMCRP ///
    $controls ///
    i.year i.ind_id, ///
    vce(cluster id)

* Test excluded instrument
test L1_PeerMCRP

* Save first-stage F statistic
scalar FirstStageF = r(F)
scalar FirstStageP = r(p)

* Store regression first
eststo FIRST

* Add diagnostics to stored result
estadd scalar FirstStageF = FirstStageF
estadd scalar FirstStageP = FirstStageP

display "First-stage F statistic = " %9.3f FirstStageF
display "First-stage p-value = " %9.4f FirstStageP


/**********************************************************************
  7. 2SLS estimation
**********************************************************************/

ivregress 2sls DD ///
    $controls ///
    i.year i.ind_id ///
    (MCRP = L1_PeerMCRP), ///
    vce(cluster id)


/**********************************************************************
  8. First-stage diagnostics
**********************************************************************/

estat firststage


/**********************************************************************
  9. Endogeneity test
**********************************************************************/

estat endogenous

* Display returned results for checking
return list

* With cluster-robust VCE, Stata reports:
* r(r_score)   = Wooldridge robust score statistic
* r(p_r_score) = p-value of robust score test
* r(regF)      = robust regression-based F statistic
* r(p_regF)    = p-value of robust regression-based test

scalar EndogScore   = r(r_score)
scalar EndogScoreP  = r(p_r_score)
scalar EndogRegF    = r(regF)
scalar EndogRegFP   = r(p_regF)

display "Robust score statistic = " %9.3f EndogScore
display "Robust score p-value = " %9.4f EndogScoreP
display "Robust regression-based F = " %9.3f EndogRegF
display "Robust regression-based p-value = " %9.4f EndogRegFP


/**********************************************************************
  10. Add diagnostics to the active 2SLS estimates
**********************************************************************/

estadd scalar EndogP      = EndogRegFP
estadd scalar EndogScoreP = EndogScoreP
estadd scalar EndogRegF   = EndogRegF

* Store AFTER adding the scalars
eststo IV1


/**********************************************************************
  11. OLS on exactly the same IV sample

  Essential for comparison with 2SLS.
**********************************************************************/

gen byte IVsample = ///
    !missing(DD, MCRP, L1_PeerMCRP, ///
             Size, Lev, ROA, Fixed, Growth, ListAge, ///
             Dual, Top1, Cashflow, Inv)

reg DD ///
    MCRP ///
    $controls ///
    i.year i.ind_id ///
    if IVsample==1, ///
    vce(cluster id)

eststo OLSsame


/**********************************************************************
  12. Export first-stage and second-stage results
**********************************************************************/

capture which esttab
if _rc ssc install estout, replace


/**********************************************************************
  Table A: First stage
**********************************************************************/

esttab FIRST ///
    using "$root/Table_IV_First_Stage.rtf", ///
    replace ///
    b(%9.3f) se(%9.3f) ///
    star(* 0.10 ** 0.05 *** 0.01) ///
    keep(L1_PeerMCRP ///
         Size Lev ROA Fixed Growth ListAge Dual Top1 Cashflow Inv ///
         _cons) ///
    order(L1_PeerMCRP ///
          Size Lev ROA Fixed Growth ListAge Dual Top1 Cashflow Inv ///
          _cons) ///
    varlabels( ///
        L1_PeerMCRP "L.Peer MCRP" ///
        Size "Size" ///
        Lev "Lev" ///
        ROA "ROA" ///
        Fixed "Fixed" ///
        Growth "Growth" ///
        ListAge "ListAge" ///
        Dual "Dual" ///
        Top1 "Top1" ///
        Cashflow "Cashflow" ///
        Inv "Inv" ///
        _cons "Constant") ///
    stats(N r2 FirstStageF FirstStageP, ///
        labels("N" ///
               "R-squared" ///
               "First-stage F-statistic" ///
               "First-stage p-value") ///
        fmt(%9.0f %9.3f %9.2f %9.4f)) ///
    title("Panel A. First-stage regression")


/**********************************************************************
  Table B: Same-sample OLS and 2SLS
**********************************************************************/

esttab OLSsame IV1 ///
    using "$root/Table_IV_2SLS.rtf", ///
    replace ///
    b(%9.3f) se(%9.3f) ///
    star(* 0.10 ** 0.05 *** 0.01) ///
    mtitles("(1) OLS" "(2) 2SLS") ///
    keep(MCRP ///
         Size Lev ROA Fixed Growth ListAge Dual Top1 Cashflow Inv ///
         _cons) ///
    order(MCRP ///
          Size Lev ROA Fixed Growth ListAge Dual Top1 Cashflow Inv ///
          _cons) ///
    varlabels( ///
        MCRP "MCRP" ///
        Size "Size" ///
        Lev "Lev" ///
        ROA "ROA" ///
        Fixed "Fixed" ///
        Growth "Growth" ///
        ListAge "ListAge" ///
        Dual "Dual" ///
        Top1 "Top1" ///
        Cashflow "Cashflow" ///
        Inv "Inv" ///
        _cons "Constant") ///
    stats(N r2 EndogP, ///
        labels("N" ///
               "R-squared" ///
               "Endogeneity test p-value") ///
        fmt(%9.0f %9.3f %9.4f)) ///
    title("Panel B. OLS and 2SLS estimates") ///
    addnotes( ///
    "The instrument is the one-year-lagged leave-one-out industry-year mean of MCRP.", ///
    "The endogeneity test reports the p-value of the robust regression-based test.", ///
    "All regressions include industry and year fixed effects.", ///
    "Standard errors are clustered at the firm level.")