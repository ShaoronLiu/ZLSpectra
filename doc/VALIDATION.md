# Application and validation

The validation case uses 24 calcium-carbonate–kaolinite spectra and 30 hematite–kaolinite spectra with known contents. See `data/sample_manifest.csv` for actual sample contents and source provenance.

## Reproduce the extraction

1. Launch `ZLSpectra` in MATLAB.
2. Choose Calcium carbonate and import `data/calcium_carbonate/spectra`. Use the 5-point/order-2 reflectance pre-smoother and the 39-point/order-2 SG derivative setting for comparison with the included output.
3. Choose Hematite and import `data/hematite/spectra`. Use the 5-point/order-2 reflectance pre-smoother and the 29-point/order-2 SG derivative setting for comparison with the included output.
4. Review the relevant band (carbonate nominal minimum/maximum 2340/2370 nm; hematite 535/580 nm nominal references). Select the actual corresponding extrema. Weak samples may need careful review; do not force an absent feature.
5. Save outputs outside the input folders and compare sample identifiers, actual selected wavelengths and amplitudes with the reference workbooks. Interactive point choices and window changes can change the result. Existing output workbooks do not necessarily record every setting in older versions.

## Plot the supplied reference results

```matlab
addpath('code');
plot_validation_reference;
```

The helper reads the original application output workbooks and creates three plots. It does not rerun spectral processing. Carbonate intensity increases approximately linearly with content. Hematite shows an approximately linear response at 0–10% and a logarithmic response at higher contents, consistent in pattern with Cao et al. (2024), Fig. 3f, and Cao et al. (2022), Fig. 7c. This is a response-reproduction case, not a claim of universal concentration accuracy or detection limits.

The manuscript timing comparison used 54 spectra: conventional processing 30 min versus ZLSpectra 10 min, a reduction of approximately 67%. These are author-reported timings, not measurements rerun while packaging this release.

## Confirmed reference workbooks

On 2026-11-27 the author confirmed the following workbooks as the validation references:

| Dataset | Workbook | Sheet | Records | Content interpretation |
|---|---|---|---:|---|
| Calcium carbonate | data/calcium_carbonate/reference_outputs/Calcium_carbonate-1117.xlsx | Calcium_carbonate | 24 | Numeric Sample ID is content in percent |
| Hematite | data/hematite/reference_outputs/Hematite_5+29_zls.xlsx | Hematite | 30 | Numeric Sample ID is mass fraction; multiply by 100 for percent |

Both workbooks contain Sample ID, Minimum (nm), Maximum (nm), and the mineral-index amplitude. Their numeric values were retained as supplied. The author reports successful full runs in MATLAB 26.1 on macOS 26.6.2 (25G83). The reference workbooks do not contain a complete per-sample processing-settings sheet; the 5/29 and 5/39 configurations are documented for the application case rather than inferred as metadata stored in these older workbooks.

## Parameter confirmation

The author confirmed a quadratic polynomial for the second-stage derivative calculation. The current code also uses quadratic first-stage smoothing for hematite and calcium carbonate: est_calculateD2 passes the same order to both stages. This is verified from the current source, not from parameter metadata in the historical reference workbooks. The first-stage order used when generating those older workbooks was not separately recalled by the author.
