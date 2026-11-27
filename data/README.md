Validation datasets
The spectra in this release were supplied by the ZLSpectra authors for the manuscript application case.
Dataset
Samples
Content range
Source
Calcium carbonate–kaolinite
24
0–100% calcium carbonate
Cao et al. (2024), doi:10.1029/2023GC011370
Hematite–kaolinite
30
0–100% hematite
Cao et al. (2022), doi:10.3390/min12070872
Contents are in percent by mass, as identified by the supplied sample filenames. The manifest preserves exact filename values, including the low-content hematite series. The zero-content samples are the backgrounds. These two datasets do not validate every mineral implemented in ZLSpectra.
File organization
- original/: supplied source files, copied byte for byte. Carbonate originals are XLSX; hematite originals are legacy-encoded CSV. Header encoding is retained in originals.
- spectra/: import-ready UTF-8 CSV, one sample per file. Two header rows (sample identifier, then column labels); columns: Wavelength_nm, Reflectance_percent. Finite numeric rows were retained and sorted by increasing wavelength. No smoothing, interpolation, K–M transformation, derivative calculation or reflectance rescaling was applied during this conversion.
- reference_outputs/: complete author-provided ZLSpectra output workbooks from the earlier application case (24 carbonate / 30 hematite records). They are example selections, not newly recalculated results or independent ground truth.
- hematite/partial_outputs/678.xlsx: supplied partial workbook containing only two selected samples; it is intentionally excluded from the raw-spectrum input folder.
- sample_manifest.csv: sample content, file paths, original hash, observation count, wavelength coverage and units.
Do not select the entire dataset root as the raw-spectrum input folder. Use only its spectra/ subfolder. The original wavelength coverage is preserved; it may be narrower than the program's maximum analysis interval.
Attribution and rights
Cao, W., et al. (2024). Semi-Quantification of the Calcium Carbonate in Marine Sediments by Visible and Near-Infrared Diffuse Reflectance Spectroscopy. Geochemistry, Geophysics, Geosystems, 25, e2023GC011370. https://doi.org/10.1029/2023GC011370
Cao, W., et al. (2022). Re-Visiting the Quantification of Hematite by Diffuse Reflectance Spectroscopy. Minerals, 12(7), 872. https://doi.org/10.3390/min12070872
The MIT license applies to ZLSpectra software and documentation, not automatically to these source datasets. The data are redistributed here as supplied by the ZLSpectra authors, with source attribution. No new data license or transfer of third-party rights is asserted by this package.
The ZLSpectra author reports that the data provider has agreed to public uploading of these two datasets. This permission statement does not assign a new blanket license to third-party data.
