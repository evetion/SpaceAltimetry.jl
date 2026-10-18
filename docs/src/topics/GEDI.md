# GEDI
GEDI—launched in 2018—is attached to the ISS and investigates global ecosystems[^dub].

We currently only support the L2A product (at version 2).

See their [website](https://gedi.umd.edu).

Use [`GEDI.Quality`](@ref) with `filter` or in an operation pipeline to apply
the full algorithm-aware L2A quality criteria used by
[`points`](@ref)`(g; filtered=true)`. Apply [`GEDI.Sensitivity`](@ref)
afterwards to retain returns above a sensitivity threshold.

[^dub]: Dubayah, Ralph, James Bryan Blair, Scott Goetz, Lola Fatoyinbo, Matthew Hansen, Sean Healey, Michelle Hofton, et al. 2020. "The Global Ecosystem Dynamics Investigation: High-Resolution Laser Ranging of the Earth's Forests and Topography." Science of Remote Sensing 1 (June): 100002. https://doi.org/10/ggjxx8.

## Products

- [L2A](gedi/L2A.md) — Ground Elevation & Canopy Height
