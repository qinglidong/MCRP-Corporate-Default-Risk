
clear all
set more off
set varabbrev off

*=====================================================================*
* 0. Paths and packages
*=====================================================================*
global root "YOUR_LOCAL_PROJECT_PATH"
local mgrfile "$root/总经理个人特征.xlsx"
local mainfile "$root/原始数据.xlsx"

capture which esttab
if _rc ssc install estout, replace

*=====================================================================*
* 1. Import and clean managerial attributes
*=====================================================================*
import excel `"`mgrfile'"', sheet("模板") firstrow allstring clear

* The source workbook has a second row containing Chinese variable labels.
drop if Symbol == "证券代码"
drop if missing(Symbol) | missing(EndDate)

* Standardize firm code and year.
replace Symbol  = ustrtrim(Symbol)
replace EndDate = ustrtrim(EndDate)
replace Symbol  = subinstr(Symbol,"'","",.)

gen long id = real(Symbol)
gen int year = real(substr(EndDate,1,4))

assert !missing(id)
assert !missing(year)
keep if inrange(year,2016,2025)

* Convert relevant source variables to numeric.
foreach v in Gender AgeID EducationBack IsCEOFilled {
    replace `v' = ustrtrim(`v')
    destring `v', replace force
}

* Remove invalid codes rather than forcing them into categories.
replace Gender        = . if !inlist(Gender,0,1)
replace AgeID         = . if !inrange(AgeID,1,5)
replace EducationBack = . if !inrange(EducationBack,1,6)
replace IsCEOFilled   = . if !inlist(IsCEOFilled,0,1)

* Managerial controls used in the reviewer-response robustness test.
* Gender in source: 0=female, 1=male.
gen byte CEOFemale = (Gender==0) if !missing(Gender)

* Age is reported as an ordered category in the source database.
gen byte CEOAgeGroup = AgeID

* Education is retained as a categorical control (1-6).
gen byte CEOEducation = EducationBack

* Keep a data-quality flag, but do NOT treat it as a managerial characteristic.
gen byte CEOFilled = IsCEOFilled

label var CEOFemale    "Female chief executive/general manager"
label var CEOAgeGroup  "Executive age category"
label var CEOEducation "Executive education category"
label var CEOFilled    "Executive attribute record filled from adjacent year"

label define ceogender 0 "Male" 1 "Female"
label values CEOFemale ceogender

label define ceoage 1 "<30" 2 "30-34" 3 "35-39" 4 "40-44" 5 ">=45"
label values CEOAgeGroup ceoage

label define ceoedu 1 "Secondary or below" 2 "College" 3 "Bachelor" ///
                    4 "Master" 5 "Doctorate" 6 "Other"
label values CEOEducation ceoedu

* Diagnostics: the source file should contain only one executive record per firm-year.
isid id year

tab year
misstable summarize CEOFemale CEOAgeGroup CEOEducation CEOFilled

tab CEOFemale, missing
tab CEOAgeGroup, missing
tab CEOEducation, missing
tab CEOFilled, missing

* Retain only variables required for merging and diagnostics.
keep id year CEOFemale CEOAgeGroup CEOEducation CEOFilled
compress
save "$root/managerial_controls_clean.dta", replace

*=====================================================================*
* 2. Import the original empirical dataset and merge
*=====================================================================*
import excel `"`mainfile'"', firstrow clear

capture confirm numeric variable id
if _rc destring id, replace force

capture confirm numeric variable year
if _rc destring year, replace force

* Verify that the original data are uniquely identified by firm-year.
isid id year

merge 1:1 id year using "$root/managerial_controls_clean.dta", ///
      keep(master match) gen(_merge_mgr)

label define mergemgr 1 "Original sample only" 3 "Matched managerial data"
label values _merge_mgr mergemgr

tab _merge_mgr

tab year _merge_mgr, row

* Do not overwrite the original source file.
save "$root/original_plus_managerial_controls.dta", replace

*=====================================================================*
* 3. Prepare regression variables
*=====================================================================*

* Industry identifier.
capture confirm variable ind_id
if _rc {
    capture confirm numeric variable Ind
    if _rc {
        encode Ind, gen(ind_id)
    }
    else {
        gen long ind_id = Ind
    }
}

* Original baseline controls in the submitted manuscript.
global controls Size Lev ROA Fixed Growth ListAge Dual Top1 Cashflow Inv

* Managerial-control completeness.
gen byte mgr_available = (_merge_mgr==3 & ///
    !missing(CEOFemale, CEOAgeGroup, CEOEducation))

label var mgr_available "Complete managerial controls available"

tab mgr_available
tab year if mgr_available

*=====================================================================*
* 4. Regression diagnostics
*=====================================================================*
eststo clear

* (A) Original baseline specification on the full available sample.
reg DD MCRP $controls i.year i.ind_id, vce(cluster id)
eststo BASE_FULL

* (B) Model requested by Reviewer #2: add managerial attributes.
reg DD MCRP $controls CEOFemale i.CEOAgeGroup i.CEOEducation ///
    i.year i.ind_id if mgr_available==1, vce(cluster id)

* Mark the exact estimation sample before running any other model.
gen byte sample_mgr = e(sample)
eststo MANAGER

* (C) Baseline specification on exactly the same sample as model (B).
reg DD MCRP $controls i.year i.ind_id if sample_mgr==1, vce(cluster id)
eststo BASE_SAME

*=====================================================================*
* 5. Display the three coefficients for quick comparison
*=====================================================================*
esttab BASE_FULL BASE_SAME MANAGER, ///
    keep(MCRP) order(MCRP) ///
    b(%9.4f) se(%9.4f) ///
    star(* 0.10 ** 0.05 *** 0.01) ///
    mtitles("Submitted baseline" "Same-sample baseline" "+ managerial controls") ///
    stats(N r2, labels("Observations" "R-squared") fmt(%9.0f %9.3f))

* Export a concise diagnostic table.
esttab BASE_FULL BASE_SAME MANAGER ///
    using "$root/managerial_controls_diagnostic.rtf", replace ///
    keep(MCRP) order(MCRP) ///
    b(%9.4f) se(%9.4f) ///
    star(* 0.10 ** 0.05 *** 0.01) ///
    mtitles("Submitted baseline" "Same-sample baseline" "+ managerial controls") ///
    stats(N r2, labels("Observations" "R-squared") fmt(%9.0f %9.3f)) ///
    addnotes("Firm-clustered standard errors are reported in parentheses.", ///
             "The third specification additionally controls for executive gender, age category, and education category.")

* Export the full managerial-control regression for internal checking.
esttab MANAGER using "$root/managerial_controls_full_regression.rtf", replace ///
    b(%9.4f) se(%9.4f) ///
    star(* 0.10 ** 0.05 *** 0.01) ///
    keep(MCRP Size Lev ROA Fixed Growth ListAge Dual Top1 Cashflow Inv ///
         CEOFemale *.CEOAgeGroup *.CEOEducation _cons) ///
    order(MCRP Size Lev ROA Fixed Growth ListAge Dual Top1 Cashflow Inv ///
          CEOFemale *.CEOAgeGroup *.CEOEducation _cons) ///
    stats(N r2, labels("Observations" "R-squared") fmt(%9.0f %9.3f)) ///
    addnotes("Firm-clustered standard errors are reported in parentheses.")

*=====================================================================*
* 6. Key coefficient values for the response letter
*=====================================================================*

* Re-run managerial model so coefficient/scalar references are current.
reg DD MCRP $controls CEOFemale i.CEOAgeGroup i.CEOEducation ///
    i.year i.ind_id if sample_mgr==1, vce(cluster id)

display as text "MCRP coefficient with managerial controls = " ///
    as result %9.4f _b[MCRP]
display as text "MCRP standard error = " ///
    as result %9.4f _se[MCRP]
display as text "Observations = " as result %12.0f e(N)
display as text "R-squared = " as result %9.4f e(r2)

save "$root/original_plus_managerial_controls.dta", replace

/**********************************************************************
 Interpretation criterion:
 - The preferred result is that MCRP remains positive and statistically significant.
 - Compare MANAGER primarily with BASE_SAME, not only BASE_FULL, because
   EducationBack has non-trivial missingness and changes the estimation sample.
 - Only the MANAGER column needs to be added to the main robustness table.
**********************************************************************/
