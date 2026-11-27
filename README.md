# ZLSpectra

A MATLAB-based graphical tool for batch processing and interactive analysis of laboratory diffuse reflectance spectra.

ZLSpectra integrates mineral-proxy extraction, interactive feature selection and review, SG guide curves, derived-proxy calculation, and configurable spectral processing. It runs in MATLAB; this release does not include a standalone executable.

## Tested environment

Author-reported successful validation: MATLAB 26.1 on macOS 26.6.2 (build 25G83), using 30 hematite and 24 calcium carbonate spectra. Dependency analysis identified MATLAB only. Windows has not yet been tested.

## Repository

https://github.com/ShaoronLiu/ZLSpectra

## Start

Download and extract the repository, open the folder in MATLAB, and run:

```matlab
ZLSpectra
```

For an example, select **Established Mineral Spectral Proxies**, choose **Hematite** or **Calcium carbonate**, and select the corresponding `data/<dataset>/spectra` folder. Save the output workbook outside the input folder. Select and confirm the mineral feature pair for each spectrum. Results depend on the selected points and processing parameters.

- [中文使用说明](doc/QUICKSTART_zh.md)
- [Installation and input formats](doc/INSTALLATION.md)
- [Illustrated user guide](doc/USER_GUIDE.md)
- [Validation workflow](doc/VALIDATION.md)
- [Data sources and attribution](data/README.md)
- [Processing methods and references](doc/METHODS.md)
- [Release checks and limitations](doc/RELEASE_CHECKS.md)

## Included functions

- Hematite, goethite, gypsum (two bands), calcium carbonate, kaolinite, illite, chlorite, the 2:1 clay-mineral group, and gibbsite proxies.
- Interactive candidate-extremum selection, review and revision.
- Adjustable SG derivative windows and overlaid guide curves. Guide curves assist interpretation; measurements use the main curve.
- Hematite characteristic absorption-band position series.
- Derived RelHm+Gt calculation from paired band intensities.
- Configurable transformations, corrections, normalization, smoothing and derivatives, with processed-data and workflow export.

## Repository layout

```text
ZLSpectra.m                 Main MATLAB GUI program
code/                       Validation plotting helper
data/                      Validation spectra and output examples
  sample_manifest.csv       Sample contents, file paths, units and provenance
  calcium_carbonate/        24 spectra, originals and reference outputs
  hematite/                 30 spectra, originals and reference outputs
doc/                       Installation, methods and validation instructions
CITATION.cff                Software citation metadata
LICENSE                     MIT license for the software
SHA256SUMS.txt              File integrity checksums
```

## Authors

Shaorong Liu, Jingyu Zhang, Qingsong Liu, Wei Cao, and Junsheng Nie.

Affiliations: Lanzhou University; Southern University of Science and Technology; Institute of Geographical Sciences, Henan Academy of Sciences. Correspondence: zhangjingyu@lzu.edu.cn; jnie@lzu.edu.cn.

## Citation

The ZLSpectra manuscript is in preparation. No journal acceptance or software DOI is asserted in this snapshot. See `CITATION.cff` for the software authors. Please also cite the original publications for the data and mineral methods you use.

## License

The software is distributed under the MIT license. The accompanying literature-derived datasets retain their original rights and attribution; see `data/README.md`. MATLAB is a separate product and is not distributed with this package.
