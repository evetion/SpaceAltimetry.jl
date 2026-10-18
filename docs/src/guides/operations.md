# Chaining Operations

`table(g)` is lazy: it keeps the HDF5 file and granule context around so
operations can auto-pull the columns they need. To keep that context across
multiple filters and transforms, use Julia's `|>` pipe syntax and materialize
only at the end:

```julia
using DataFrames
using Extents
using SpaceAltimetry

g = granule("GLAH14_634_1102_001_0071_0_01_0001.H5")
ext = Extent(X = (-180.0, 0.0), Y = (60.0, 80.0))

df = table(g) |>
    ICESat.SaturationCorrect() |>
    InExtent(ext) |>
    ICESat.Quality() |>
    DataFrame
```

The intermediate operations above are lazy. SpaceAltimetry first gathers the union
of required columns, reads the HDF5 data once, then applies the operations in
left-to-right pipe order. `DataFrame` can be replaced by `collect` if you want
SpaceAltimetry's lightweight `Table`/`PartitionedTable` wrappers instead.

The two-argument verbs remain eager:

```julia
t = table(g)
t1 = map(ICESat.SaturationCorrect(), t) # materializes
t2 = filter(ICESat.Quality(), t1) # cannot auto-pull missing HDF5 columns
```

Use the eager `filter`/`map` form for a single operation, or after you have
already selected/materialized every column needed by later operations.

Mission-specific operations live in exported namespaces so common names remain
short without colliding:

| Mission | Operations |
|:--|:--|
| `ICESat` | [`Quality`](@ref ICESat.Quality), [`SaturationCorrect`](@ref ICESat.SaturationCorrect), [`TopexToWGS84`](@ref ICESat.TopexToWGS84) |
| `ICESat2` | [`Quality`](@ref ICESat2.Quality) for ATL03, ATL06, and ATL08 |
| `GEDI` | [`Quality`](@ref GEDI.Quality) for the full L2A composite quality filter; [`Sensitivity`](@ref GEDI.Sensitivity) for `gt < sensitivity <= 1.0` |

For example, [`ICESat2.Quality`](@ref) in
`filter(ICESat2.Quality(), table(atl06))` keeps the same high-quality subset
identified by the ATL06 point method. [`GEDI.Quality`](@ref) in
`filter(GEDI.Quality(), table(gedi))` applies the complete algorithm-aware
filter used by [`points`](@ref)`(gedi; filtered=true)`. Pipe
[`GEDI.Sensitivity`](@ref) after it to keep returns above a sensitivity
threshold (0.9 by default).
