/***********************************************************************
  Reviewer #2 additional analysis:
  Media scrutiny / media attention

  Main data:
  G:\联合指导\连兰兰合作论文\paper 4\论文+数据+代码\原始数据.xlsx

  Media data:
  G:\联合指导\连兰兰合作论文\paper 4\论文+数据+代码\媒体关注数据.xlsx

  Main variables:
      DD      = distance to default
      MCRP    = managerial climate risk perception

  Media variables:
      SocialMediaOversight = media scrutiny
      MediaSentiment       = media sentiment/tone

  Design:
      A. Data diagnostics
      B. Merge media data with original sample
      C. High vs. low media scrutiny regressions
      D. Formal coefficient-difference tests
      E. Continuous interaction tests
      F. Optional media-sentiment tests
***********************************************************************/

clear all
set more off
set varabbrev off

/***********************************************************************
  0. Paths
***********************************************************************/

global root  "G:/联合指导/连兰兰合作论文/paper 4/论文+数据+代码"
global main  "$root/原始数据.xlsx"
global media "$root/媒体关注数据.xlsx"
global out   "$root/media_attention_results"

capture mkdir "$out"

cd "$root"

capture which esttab
if _rc ssc install estout, replace


/***********************************************************************
  1. Import original dataset
***********************************************************************/

import excel "$main", firstrow clear

* Core variables
capture confirm variable DD
if _rc {
    display as error "DD not found in original data."
    exit 111
}

capture confirm variable MCRP
if _rc {
    display as error "MCRP not found in original data."
    exit 111
}

* Firm identifier
capture confirm numeric variable id
if _rc destring id, replace ignore(" ")

* Year
capture confirm numeric variable year
if _rc destring year, replace ignore(" ")

* Industry identifier
capture drop ind_id

capture confirm numeric variable Ind
if _rc {
    encode Ind, gen(ind_id)
}
else {
    gen long ind_id = Ind
}

* Check firm-year uniqueness
isid id year

* Restrict to paper sample period
keep if inrange(year, 2016, 2025)

tempfile original
save `original', replace


/***********************************************************************
  2. Import media dataset

  The uploaded Excel contains:
      Row 1 = English variable names
      Row 2 = Chinese variable descriptions
      Row 3 = units
      Row 4 onward = actual observations

  allstring is used to preserve leading zeros in Symbol.
***********************************************************************/

import excel "$media", firstrow clear allstring

* Remove metadata rows
drop if Symbol == "证券代码"
drop if missing(Symbol)

* Construct numeric firm ID from 6-digit stock code
gen long id = real(Symbol)

* Construct year
gen int year = real(substr(EndDate,1,4))

keep if inrange(year,2016,2025)

* Convert relevant media variables to numeric
foreach v in SocialMediaOversight MediaSentiment {
    capture confirm numeric variable `v'
    if _rc destring `v', replace force
}

rename SocialMediaOversight MediaScrutiny
rename MediaSentiment       MediaTone

label var MediaScrutiny "Media scrutiny"
label var MediaTone     "Media sentiment"

keep id year MediaScrutiny MediaTone

/***********************************************************************
  2.1 Diagnostics
***********************************************************************/

display "======================================================="
display "MEDIA DATA DIAGNOSTICS"
display "======================================================="

describe id year MediaScrutiny MediaTone

summarize MediaScrutiny MediaTone, detail

misstable summarize MediaScrutiny MediaTone

duplicates report id year
isid id year

* IMPORTANT diagnostic:
* Dictionary defines MediaScrutiny as ln(1 + negative news count),
* which theoretically should not be negative.
count if MediaScrutiny < 0 & !missing(MediaScrutiny)

if r(N)>0 {
    display as error ///
    "WARNING: MediaScrutiny contains negative values."
    display as error ///
    "This is inconsistent with the dictionary definition ln(1 + negative news count)."
    display as error ///
    "Verify whether the source variable has been standardized or recoded before interpretation."
}

* MediaTone theoretically ranges from -1 to +1 according to its formula
count if (MediaTone < -1 | MediaTone > 1) & !missing(MediaTone)

if r(N)>0 {
    display as error ///
    "WARNING: MediaTone contains observations outside [-1,1]."
}

tempfile media
save `media', replace


/***********************************************************************
  3. Merge with original sample
***********************************************************************/

use `original', clear

merge 1:1 id year using `media', gen(_merge_media)

tab _merge_media

count
local N_all = r(N)

count if _merge_media==3
local N_match = r(N)

display "Original observations = `N_all'"
display "Matched media observations = `N_match'"
display "Match rate = " %6.2f (100*`N_match'/`N_all') "%"

* Keep original sample; regressions automatically exclude missing media
drop if _merge_media==2
drop _merge_media

/***********************************************************************
  3.1 Media-variable coverage in the regression sample
***********************************************************************/

summarize MediaScrutiny MediaTone, detail
misstable summarize MediaScrutiny MediaTone

tab year if !missing(MediaScrutiny)
tab year if !missing(MediaTone)


/***********************************************************************
  4. Declare panel
***********************************************************************/

xtset id year

capture drop L1_MCRP
gen L1_MCRP = L.MCRP

label var L1_MCRP "Lagged MCRP"


/***********************************************************************
  5. Baseline control variables
***********************************************************************/

global controls ///
    Size Lev ROA Fixed Growth ListAge Dual Top1 Cashflow Inv


/***********************************************************************
  6. Construct high/low media-scrutiny groups

  Preferred approach:
  Industry-year median.

  Reason:
  Media coverage differs systematically across industries and years.
***********************************************************************/

capture drop MediaMedian HighMedia

bysort ind_id year: egen MediaMedian = median(MediaScrutiny)

gen byte HighMedia = ///
    MediaScrutiny > MediaMedian ///
    if !missing(MediaScrutiny, MediaMedian)

label define highmedia ///
    0 "Low media scrutiny" ///
    1 "High media scrutiny"

label values HighMedia highmedia

tab HighMedia
tab HighMedia year


/***********************************************************************
  7. Table: Media-scrutiny cross-sectional analysis

  Structure matches existing Sections 4.4.1 and 4.4.2:

  (1) High media: contemporaneous MCRP
  (2) High media: lagged MCRP
  (3) Low media : contemporaneous MCRP
  (4) Low media : lagged MCRP
***********************************************************************/

eststo clear


/*--------------------------------------------------
  Column (1): High media scrutiny, MCRP
--------------------------------------------------*/

reg DD MCRP $controls i.year i.ind_id ///
    if HighMedia==1, ///
    vce(cluster id)

eststo MED1


/*--------------------------------------------------
  Column (2): High media scrutiny, lagged MCRP
--------------------------------------------------*/

reg DD L1_MCRP $controls i.year i.ind_id ///
    if HighMedia==1, ///
    vce(cluster id)

eststo MED2


/*--------------------------------------------------
  Column (3): Low media scrutiny, MCRP
--------------------------------------------------*/

reg DD MCRP $controls i.year i.ind_id ///
    if HighMedia==0, ///
    vce(cluster id)

eststo MED3


/*--------------------------------------------------
  Column (4): Low media scrutiny, lagged MCRP
--------------------------------------------------*/

reg DD L1_MCRP $controls i.year i.ind_id ///
    if HighMedia==0, ///
    vce(cluster id)

eststo MED4

	
/***********************************************************************
  8. Export cross-sectional table
     Report all control variables and constant
***********************************************************************/

esttab MED1 MED2 MED3 MED4 ///
    using "$out/Table_Media_Scrutiny_Heterogeneity.rtf", ///
    replace ///
    b(%9.3f) se(%9.3f) ///
    star(* 0.10 ** 0.05 *** 0.01) ///
    nodepvars nonumbers ///
    mtitles("(1) High media" ///
            "(2) High media" ///
            "(3) Low media" ///
            "(4) Low media") ///
    keep(MCRP L1_MCRP ///
         Size Lev ROA Fixed Growth ListAge Dual Top1 Cashflow Inv ///
         _cons) ///
    order(MCRP L1_MCRP ///
          Size Lev ROA Fixed Growth ListAge Dual Top1 Cashflow Inv ///
          _cons) ///
    varlabels( ///
        MCRP     "MCRP" ///
        L1_MCRP  "L.MCRP" ///
        Size     "Size" ///
        Lev      "Lev" ///
        ROA      "ROA" ///
        Fixed    "Fixed" ///
        Growth   "Growth" ///
        ListAge  "ListAge" ///
        Dual     "Dual" ///
        Top1     "Top1" ///
        Cashflow "Cashflow" ///
        Inv      "Inv" ///
        _cons    "Constant" ///
    ) ///
    stats(N r2, ///
        labels("N" "R-squared") ///
        fmt(%9.0f %9.3f)) ///
    title("Media scrutiny and the MCRP-DD relation") ///
    addnotes( ///
    "High-media firms are defined relative to the industry-year median of media scrutiny.", ///
    "All regressions include industry and year fixed effects.", ///
    "Standard errors clustered at the firm level are reported in parentheses.", ///
    "***, **, and * indicate significance at the 1%, 5%, and 10% levels, respectively.")
	

/***********************************************************************
  9. FORMAL DIFFERENCE TEST
     This part is essential.

     Separate-group significance is NOT evidence that coefficients differ.

     The interaction coefficient directly tests:
         High-media coefficient - Low-media coefficient
***********************************************************************/

eststo clear


/*--------------------------------------------------
  Column (1): contemporaneous MCRP
--------------------------------------------------*/

reg DD ///
    c.MCRP##i.HighMedia ///
    $controls ///
    i.year i.ind_id ///
    if !missing(MediaScrutiny), ///
    vce(cluster id)

eststo DIFF1

test 1.HighMedia#c.MCRP

scalar p_media_current = r(p)

display "P-value for difference in contemporaneous MCRP coefficients:"
display p_media_current


/*--------------------------------------------------
  Column (2): lagged MCRP
--------------------------------------------------*/

reg DD ///
    c.L1_MCRP##i.HighMedia ///
    $controls ///
    i.year i.ind_id ///
    if !missing(MediaScrutiny), ///
    vce(cluster id)

eststo DIFF2

test 1.HighMedia#c.L1_MCRP

scalar p_media_lag = r(p)

display "P-value for difference in lagged MCRP coefficients:"
display p_media_lag


/***********************************************************************
  10. Export formal difference tests
***********************************************************************/

esttab DIFF1 DIFF2 ///
    using "$out/Table_Media_Scrutiny_Difference_Test.rtf", ///
    replace ///
    b(%9.3f) se(%9.3f) ///
    star(* 0.10 ** 0.05 *** 0.01) ///
    nodepvars nonumbers ///
    mtitles("(1) MCRP" "(2) L.MCRP") ///
    keep(MCRP L1_MCRP ///
         1.HighMedia ///
         1.HighMedia#c.MCRP ///
         1.HighMedia#c.L1_MCRP) ///
    varlabels( ///
        MCRP "MCRP" ///
        L1_MCRP "L.MCRP" ///
        1.HighMedia "High media scrutiny" ///
        1.HighMedia#c.MCRP "MCRP × High media" ///
        1.HighMedia#c.L1_MCRP "L.MCRP × High media" ///
    ) ///
    stats(N r2, ///
        labels("N" "R-squared") ///
        fmt(%9.0f %9.3f)) ///
    title("Coefficient-difference tests: media scrutiny") ///
    addnotes( ///
    "The interaction coefficient tests whether the MCRP-DD relation differs between high- and low-media-scrutiny firms.", ///
    "All regressions include controls, industry fixed effects, and year fixed effects.", ///
    "Standard errors clustered at the firm level are reported in parentheses.")


/***********************************************************************
  11. Continuous interaction test

  This avoids the arbitrary nature of median splitting and should be
  retained internally even if the paper reports only the group results.
***********************************************************************/

capture drop zMediaScrutiny

egen zMediaScrutiny = std(MediaScrutiny)

label var zMediaScrutiny "Standardized media scrutiny"

eststo clear


/* Current MCRP */

reg DD ///
    c.MCRP##c.zMediaScrutiny ///
    $controls ///
    i.year i.ind_id, ///
    vce(cluster id)

eststo CONT1


/* Lagged MCRP */

reg DD ///
    c.L1_MCRP##c.zMediaScrutiny ///
    $controls ///
    i.year i.ind_id, ///
    vce(cluster id)

eststo CONT2


esttab CONT1 CONT2 ///
    using "$out/Table_Media_Scrutiny_Continuous.rtf", ///
    replace ///
    b(%9.3f) se(%9.3f) ///
    star(* 0.10 ** 0.05 *** 0.01) ///
    nodepvars nonumbers ///
    mtitles("(1) MCRP" "(2) L.MCRP") ///
    keep(MCRP L1_MCRP ///
         zMediaScrutiny ///
         c.MCRP#c.zMediaScrutiny ///
         c.L1_MCRP#c.zMediaScrutiny) ///
    varlabels( ///
        MCRP "MCRP" ///
        L1_MCRP "L.MCRP" ///
        zMediaScrutiny "Media scrutiny" ///
        c.MCRP#c.zMediaScrutiny "MCRP × Media scrutiny" ///
        c.L1_MCRP#c.zMediaScrutiny "L.MCRP × Media scrutiny" ///
    ) ///
    stats(N r2, ///
        labels("N" "R-squared") ///
        fmt(%9.0f %9.3f)) ///
    title("Continuous interaction tests: media scrutiny")


/***********************************************************************
  12. OPTIONAL: Media sentiment

  Media sentiment is conceptually different from media attention.
  Therefore this should NOT replace the main media-scrutiny analysis.

  It can be used as an additional / supplementary test.
***********************************************************************/

capture drop zMediaTone

egen zMediaTone = std(MediaTone)

label var zMediaTone "Standardized media sentiment"

eststo clear


/* Current MCRP */

reg DD ///
    c.MCRP##c.zMediaTone ///
    $controls ///
    i.year i.ind_id, ///
    vce(cluster id)

eststo TONE1


/* Lagged MCRP */

reg DD ///
    c.L1_MCRP##c.zMediaTone ///
    $controls ///
    i.year i.ind_id, ///
    vce(cluster id)

eststo TONE2


esttab TONE1 TONE2 ///
    using "$out/Table_Media_Sentiment_Additional.rtf", ///
    replace ///
    b(%9.3f) se(%9.3f) ///
    star(* 0.10 ** 0.05 *** 0.01) ///
    nodepvars nonumbers ///
    mtitles("(1) MCRP" "(2) L.MCRP") ///
    keep(MCRP L1_MCRP ///
         zMediaTone ///
         c.MCRP#c.zMediaTone ///
         c.L1_MCRP#c.zMediaTone) ///
    varlabels( ///
        MCRP "MCRP" ///
        L1_MCRP "L.MCRP" ///
        zMediaTone "Media sentiment" ///
        c.MCRP#c.zMediaTone "MCRP × Media sentiment" ///
        c.L1_MCRP#c.zMediaTone "L.MCRP × Media sentiment" ///
    ) ///
    stats(N r2, ///
        labels("N" "R-squared") ///
        fmt(%9.0f %9.3f)) ///
    title("Additional analysis: media sentiment")


/***********************************************************************
  13. Save merged dataset
***********************************************************************/

save "$out/MCRP_media_merged.dta", replace

display "======================================================="
display "MEDIA ATTENTION ANALYSIS COMPLETED"
display "======================================================="
display "Main heterogeneity table:"
display "$out/Table_Media_Scrutiny_Heterogeneity.rtf"
display ""
display "Formal difference test:"
display "$out/Table_Media_Scrutiny_Difference_Test.rtf"
display ""
display "Continuous interaction:"
display "$out/Table_Media_Scrutiny_Continuous.rtf"
display ""
display "Optional media sentiment test:"
display "$out/Table_Media_Sentiment_Additional.rtf"