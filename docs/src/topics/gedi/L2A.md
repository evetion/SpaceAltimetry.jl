# L2A — Ground Elevation & Canopy Height

Version 2 — [User Guide](https://lpdaac.usgs.gov/documents/998/GEDI02_UserGuide_V21.pdf) · [ATBD](https://lpdaac.usgs.gov/documents/581/GEDI_WF_ATBD_v1.0.pdf)
Version 3 — [User Guide](https://lpdaac.usgs.gov/documents/2442/GEDI02_User_Guide_V3.pdf) · [Data dictionary](https://lpdaac.usgs.gov/documents/2439/gedi_l2a_v3_product_data_dictionary.html)

```@setup gedi
using SpaceAltimetry
using SpaceAltimetry.H5Tables: ToDateTime, ToDateTimeConst, ToBool, InvertBool, SliceRow
using Markdown

function resolved_type(v)
    f = v.f
    if f isa ToDateTime || f isa ToDateTimeConst
        "DateTime"
    elseif f isa ToBool || f isa InvertBool
        "Bool"
    else
        string(v.eltype)
    end
end

function vars_table(vars; attrs=nothing)
    header = "| Column | HDF5 Path | Type |\n|:---|:---|:---|\n"
    rows = ["`$(v.name)` | `$(v.path)` | $(resolved_type(v))" for v in vars]
    if attrs !== nothing
        for a in attrs
            rows = push!(rows, "`$(a.name)` | attribute | $(a.eltype == Any ? "—" : string(a.eltype))")
        end
    end
    Markdown.parse(header * join(["| " * r * " |" for r in rows], "\n"))
end

dummy(T) = T("", "", (;), [])
```

## Overview

GEDI L2A provides ground elevation, canopy height metrics, and relative height
(RH) metrics for each GEDI footprint. Data is organized by 8 beams.

## Quick Start

```julia
using SpaceAltimetry, DataFrames

g = granule("GEDI02_A_2019242104318_O04046_01_T02343_02_003_02_V002.h5")
t = table(g)
df = DataFrame(t)
```

## Default Columns

```@example gedi
g = dummy(GEDI_Granule{:GEDI02_A}) # hide
vars_table(SpaceAltimetry.default_variables(g); attrs=SpaceAltimetry.default_attributes(g)) # hide
```

## Default Tracks

```@example gedi
SpaceAltimetry.default_tracks(g)
```

## Canopy Heights

Use `gedi_l2a_canopy_variables(g)` to read highest return instead of lowest mode:

```julia
t = table(g; variables=gedi_l2a_canopy_variables(g))
```

Passing the granule picks the `quality` flag of its product version; without it
the version 2 flag is used.

This reads `elev_highestreturn` / `lon_highestreturn` / `lat_highestreturn`.

## Quality Filtering

```julia
filtered = t |>
    GEDI.Quality() |>
    GEDI.Sensitivity(gt = 0.9) |>
    collect
```

The [`GEDI.Quality`](@ref) filter auto-loads the receive assessment,
stale/degrade, amplitude, and selected algorithm fields required by the full
[`points`](@ref)`(g; filtered=true)` predicate. The optional
[`GEDI.Sensitivity`](@ref) filter keeps `gt < sensitivity <= 1.0`; `gt`
defaults to `0.9`.

## Version 3

Version 3 (PGE 004, filenames ending in `_V003.h5`) is read with the same
schema, with these differences (GEDI Level 2 User Guide V3.0, section 7.1):

| | version 2 | version 3 |
|:--|:--|:--|
| `quality` column | `quality_flag` | `l2a_quality_flag_rel3`: the version 2 conditions plus `sensitivity_a2 > 0.95` over land (`> 0.98` in tropical forest) and `elev_highestreturn − digital_elevation_model < 150` m. The version 2 flag is still in the file as `l2a_quality_flag_rel2`. |
| algorithm setting groups | 1–6 | 1, 2, 5, 10 |
| [`GEDI.Quality`](@ref) algorithm checks | `rx_processing_aN/{rx_algrunflag, zcross, toploc}` of the selected group | `l2_algrunflag`, which combines the same checks and adds `0 < sensitivity < 1` |

```julia
gs = search(:GEDI, :GEDI02_A; version = 3, extent = extent)
```

!!! note "`selected_algorithm` in version 3"
    In version 3 files, `selected_algorithm` keeps the version 2 `valid_range` of
    1–6, but shots also use group 10. Because nodata masking honours `valid_range`,
    those shots read as `missing` when you add `selected_algorithm` as a column.
    `GEDI.Quality` uses `l2_algrunflag` instead, so it is not affected.
