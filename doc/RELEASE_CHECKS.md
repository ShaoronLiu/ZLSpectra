# Release checks

Packaging snapshot: 2026-11-25.

- Verified 54 import-ready spectra: 24 carbonate and 30 hematite.
- Verified finite numeric wavelength/reflectance pairs, unique ascending wavelengths, valid percent-reflectance bounds and sufficient points.
- Preserved source files byte for byte, with SHA-256 hashes in the manifest.
- Excluded hidden files, temporary Office files and .DS_Store.
- Separated the partial 678.xlsx workbook from input spectra.
- Included 24/30-record historical reference outputs separately.
- Copied the current ZLSpectra.m without rewriting numerical processing during packaging.
- The author reports successful complete runs of both validation cases (30 hematite and 24 carbonate spectra) using ZLSpectra.m on macOS 26.6.2, build 25G83, with MATLAB product version 26.1. These runs were not independently observed during packaging.
- Dependency analysis reported MATLAB only (Certain = 1). Windows has not been tested. The author-confirmed reference workbooks contain 30 hematite records and 24 carbonate records; both match the previously packaged reference files. These older workbooks have no complete per-sample parameter sheet.
- Data license terms are not assigned by the software MIT license; data source attribution is retained.

Before tagging a public release, confirm any parameters not stored in the older reference workbooks. The tested configuration does not establish a minimum MATLAB release or Windows compatibility.

## Repository preparation update

Repository address supplied by author: https://github.com/ShaoronLiu/ZLSpectra . Public file availability was not independently verified during packaging. An illustrated English user guide and manuscript code-availability wording are included. The author confirmed the second-stage quadratic polynomial and reports permission from the data provider for public uploading.
