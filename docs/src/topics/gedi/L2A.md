# L2A — Ground Elevation & Canopy Height

Version 2 — [User Guide](https://lpdaac.usgs.gov/documents/998/GEDI02_UserGuide_V21.pdf) · [ATBD](https://lpdaac.usgs.gov/documents/581/GEDI_WF_ATBD_v1.0.pdf)

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

Use `gedi_l2a_canopy_variables()` to read highest return instead of lowest mode:

```julia
t = table(g; variables=gedi_l2a_canopy_variables())
```

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
