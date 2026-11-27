# Installation and inputs

## Requirements

Use desktop MATLAB with GUI support. The entry point is `ZLSpectra.m`. No compiled application is included.

### Author-reported tested environment

| Component | Tested configuration |
|---|---|
| Operating system | macOS 26.6.2 (build 25G83) |
| MATLAB product version | 26.1 |
| Entry file | ZLSpectra.m |
| Validation cases | Complete processing of 30 hematite spectra and 24 calcium carbonate spectra; both reported successful by the author |
| Dependency analysis | MATLAB only (product number 1; Certain = 1); no additional products identified by requiredFilesAndProducts |
| Windows | Not yet tested |

The tested MATLAB version is not a verified minimum version. Dependency analysis does not by itself validate every execution path. The program uses modern MATLAB functions including `uifigure`, `uigridlayout`, `readcell`, and `readmatrix`; older releases may not support these functions.

The SG calculations are implemented in the source. Before deployment, MATLAB can report dependencies with:

```matlab
[files,products] = matlab.codetools.requiredFilesAndProducts('ZLSpectra.m');
disp(products)
```

## Run

Set the repository root as the MATLAB Current Folder and enter `ZLSpectra`. Alternatively add the root folder to the MATLAB path. No user-specific absolute paths are required by the release instructions.

## Inputs

Supported file extensions: CSV, TXT, ASC, DAT, XLSX and XLS. Each spectrum occupies a wavelength/reflectance column pair, with wavelengths in nm. Multiple samples may be arranged as adjacent column pairs. For the supplied examples, use `spectra/` CSV files, whose reflectance values are percentages.

## Outputs

Select a new output workbook in a separate results folder. The software saves mineral selections and processing information to Excel. The configurable module exports processed spectra, selected features and the workflow record. Do not overwrite the supplied reference outputs.
