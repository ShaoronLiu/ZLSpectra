# Processing and references

The standard mineral workflow interpolates reflectance onto a 1 nm grid, applies a 5-point quadratic SG pre-smoother, converts to F(R)=(1-R)^2/(2R), and calculates a SG second derivative. Default derivative windows: hematite/goethite 29 points (order 2), gypsum/carbonate 39 (order 2), clay proxies 41 (order 2), gibbsite 25 (order 3). Adjustable settings are recorded where supported by the output workflow.

The 5/29 sequence is motivated by Hu et al. (2016), which reports Varian factors of 5 and 29 on measurements at 0.5 nm spacing. This release uses a 1 nm grid and local polynomial-order choices, so identical numerical factors do not establish an identical wavelength smoothing scale. The 41-point clay window is local; it is not asserted to reproduce the published 40-smoothing-point implementation. Added five-point pre-smoothing is also a local choice for mineral methods that did not report it.

Goethite references are 425/455 nm nominal selection guides. Jiang et al. (2014) supports the approximately 425 nm second-derivative feature and the adjacent-maximum intensity definition; 455 nm is a local nominal guide, not a fixed peak required for every sample. Hematite references draw on Liu et al. (2011). Feature shifts and mineral overlap require interpretation.

The 2:1 clay proxy represents a mineral group, not individual illite/chlorite/vermiculite/montmorillonite contents. RelHm+Gt is a relative population-normalized proxy, not an absolute dust mass percentage or flux. The 550 nm hematite line is contextual, not a universal climatic threshold.

## References

- Savitzky and Golay (1964). https://doi.org/10.1021/ac60214a047
- Hu et al. (2016). https://doi.org/10.1002/2015JB012635
- Jiang et al. (2014). https://doi.org/10.1093/gji/ggt377
- Liu et al. (2011). https://doi.org/10.1180/claymin.2011.046.1.137
- Torrent and Barrón (2008). https://doi.org/10.2136/sssabookser5.5.c13
- Cao et al. (2022). https://doi.org/10.3390/min12070872
- Cao et al. (2024). https://doi.org/10.1029/2023GC011370
- Zhang et al. (2025). https://doi.org/10.1029/2024GC012118
- Poppiel et al. (2020). https://doi.org/10.3390/rs12071197
- Coblinski et al. (2021). https://doi.org/10.1016/j.catena.2021.105334
- Rosin et al. (2023). https://doi.org/10.1016/j.geoderma.2023.116413
