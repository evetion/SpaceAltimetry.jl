const gedi_tracks = ("BEAM0000", "BEAM0001", "BEAM0010", "BEAM0011", "BEAM0101", "BEAM0110", "BEAM1000", "BEAM1011")
const gedi_date_format = dateformat"yyyymmddHHMMSS"
const gedi_inclination = 51.6443

"""
    GEDI_Granule{product} <: Granule

A granule of the GEDI product `product`. Normally created automatically from
either [`search`](@ref), [`granule`](@ref) or [`granules`](@ref).
"""
Base.@kwdef mutable struct GEDI_Granule{product} <: Granule
    const id::AbstractString
    url::AbstractString
    const info::NamedTuple
    const polygons::MultiPolygonType = MultiPolygonType()
end

sproduct(::GEDI_Granule{product}) where {product} = product
mission(::GEDI_Granule) = :GEDI

default_tracks(::GEDI_Granule) = gedi_tracks

function Base.copy(g::GEDI_Granule{product}) where {product}
    GEDI_Granule{product}(g.id, g.url, g.info, copy(g.polygons))
end


"""
    info(g::GEDI_Granule)

Derive info based on the filename. This is built up as follows:
`GEDI02_A_2019110014613_O01991_T04905_02_001_01.h5`
or since version 2: `GEDI02_A_2019242104318_O04046_01_T02343_02_003_02_V002.h5`
(version 3: `GEDI02_A_2020257225350_O09946_02_T08506_02_004_02_V003.h5`).
See section 2.4 in the user guide.
"""
function info(g::GEDI_Granule)
    gedi_info(id(g))
end

function gedi_info(filename)
    id, _ = splitext(basename(filename))
    if occursin(r"_V\d{3}$", id)
        type, name, datetime, orbit, sub_orbit, track, ppds, pge_version, revision, version = Base.split(id, "_")
        version = version[2:end]
    else
        type, name, datetime, orbit, track, ppds, version, revision = Base.split(id, "_")
    end
    days = Day(parse(Int, datetime[5:7]) - 1)  # Stored as #days in year
    datetime = datetime[1:4] * "0101" * datetime[8:end]
    (
        type = Symbol(type * "_" * name),
        date = DateTime(datetime, gedi_date_format) + days,
        orbit = parse(Int32, orbit[2:end]),
        sub_orbit = parse(Int8, sub_orbit),
        track = parse(Int32, track[2:end]),
        ppds = parse(Int8, ppds),
        pge_version = parse(Int8, pge_version),
        version = parse(Int, version),
        revision = parse(Int, revision),
    )
end

"""
    gedi_version(g::GEDI_Granule)

Product version of `g` from the `_V00x` suffix of its filename. Filenames
without that suffix (version 1, or an empty id) count as version 2, which has
the same layout.
"""
function gedi_version(g::GEDI_Granule)
    stem = first(splitext(basename(id(g))))
    m = match(r"_V(\d{3})$", stem)
    return isnothing(m) ? 2 : parse(Int, m.captures[1])
end

"""
    gedi_algorithms(g::GEDI_Granule)

The algorithm setting groups (`rx_processing_aN`) present in an L2A granule.
Version 3 removed the unused groups 3, 4 and 6 and added group 10
(GEDI Level 2 User Guide V3.0, section 7.1).
"""
gedi_algorithms(g::GEDI_Granule) = gedi_version(g) >= 3 ? (1, 2, 5, 10) : (1, 2, 3, 4, 5, 6)

"""
    gedi_quality_path(g::GEDI_Granule)

Path of the shot-level L2A quality flag. Version 3 replaced `quality_flag` with
`l2a_quality_flag_rel3`, which adds sensitivity thresholds (0.95 over land, 0.98
in tropical forest) and a check of the highest return against the TanDEM-X DEM;
the version 2 flag is kept as `l2a_quality_flag_rel2` (GEDI Level 2 User Guide V3.0).
"""
gedi_quality_path(g::GEDI_Granule) = gedi_version(g) >= 3 ? "l2a_quality_flag_rel3" : "quality_flag"

"""
    track_angle(::GEDI_Granule, latitude = 0.0)

Rough approximation of the track angle (0° is North) of ICESat-2 at a given `latitude`.

# Examples

```jlcon
julia> g = GEDI_Granule(:GEDI02_A, "GEDI02_A_2019242104318_O04046_01_T02343_02_003_02_V002.h5", "", (;))
julia> track_angle(g, 0.0)
38.24944944866377
```
"""
function track_angle(g::GEDI_Granule, latitude = 0.0, nparts = 100)

    latitudes, _, angles = greatcircle(0.0, 0.0, gedi_inclination, 85.0, nparts)
    clamp!(angles, 0, 90)
    v, i = findmin(abs.(latitudes .- min(abs(latitude), gedi_inclination)))
    a = angles[i]

    info = gedi_info(id(g))
    if info.sub_orbit <= 2  # ascending
        return a
    else
        return 180 - a
    end
end

module GEDI

using Tables: Tables
using ..SpaceAltimetry: Filter, GEDI_Granule, Variable, _namevar, _var, gedi_algorithms, gedi_version
import ..SpaceAltimetry: _inputs, _mask

export Quality, Sensitivity

"""
    Quality()

Filter GEDI L2A rows using the criteria by [^l3], except for the sensitivity field, which can be manually filtered to be above 0.9 and below or equal to 1.0 to match[^l3].

[^l3]: Dubayah, R. O., S. B. Luthcke, T. J. Sabaka, J. B. Nicholas, S. Preaux, and M. A. Hofton. 2021. “GEDI L3 Gridded Land Surface Metrics, Version 2.” ORNL DAAC, November. https://doi.org/10.3334/ORNLDAAC/1952.

The filter auto-loads the following datasets:

| Dataset | Required value | Purpose |
|:--|:--|:--|
| `rx_assess/quality_flag` | nonzero | Receive waveform passed basic assessment |
| `surface_flag` | nonzero | Lowest detected mode is within 300 m of the reference surface |
| `geolocation/stale_return_flag` | zero | Geolocation does not use a stale return |
| `rx_assess/rx_maxamp / rx_assess/sd_corrected` | at least 8 | Return amplitude is sufficiently above noise |
| `degrade_flag` | zero | Instrument was not in a degraded state |
| `selected_algorithm` | an algorithm setting group in the granule | Identifies the waveform algorithm used for this shot |
| `rx_processing_aN/rx_algrunflag` | nonzero | The selected algorithm ran successfully |
| `rx_processing_aN/zcross` | greater than zero | The selected algorithm found a valid lower threshold crossing |
| `rx_processing_aN/toploc` | greater than zero | The selected algorithm found a valid waveform top |

For the final three checks, `N` is chosen independently for each row from
`selected_algorithm`; fields for all algorithm setting groups of the granule are
loaded so mixed algorithm selections can be filtered in one pass. Missing values,
algorithms without columns, and failed criteria reject the row.

For version 3 granules the last four rows are replaced by `l2_algrunflag` (nonzero),
which combines the same checks for the selected algorithm and adds
`0 < sensitivity < 1` (GEDI Level 2 User Guide V3.0). Version 3 has algorithm
setting groups 1, 2, 5 and 10 instead of 1–6 (see
[`gedi_algorithms`](@ref SpaceAltimetry.gedi_algorithms)).

`Quality` does not include the sensitivity thresholds of the version 3
`l2a_quality_flag_rel3` (the `quality` column of version 3 tables). Sensitivity is
intentionally separate; compose this filter with
[`Sensitivity`](@ref GEDI.Sensitivity) when needed.
"""
struct Quality <: Filter end

const _quality_names = (
    :rx_assess_quality,
    :surface,
    :stale_return,
    :rx_maxamp,
    :sd_corrected,
    :degrade,
)
# Highest algorithm setting group number in any L2A version (version 3 has group 10).
const _max_algorithm = 10

function _inputs(::Quality, g::GEDI_Granule{:GEDI02_A})
    variables = Variable[
        Variable(:rx_assess_quality, "rx_assess/quality_flag", UInt8),
        Variable(:surface, "surface_flag", UInt8),
        Variable(:stale_return, "geolocation/stale_return_flag", UInt8),
        Variable(:rx_maxamp, "rx_assess/rx_maxamp", Float32),
        Variable(:sd_corrected, "rx_assess/sd_corrected", Float32),
        Variable(:degrade, "degrade_flag", UInt8),
    ]
    if gedi_version(g) >= 3
        # Version 3 combines the selected algorithm's checks (rx_algrunflag,
        # zcross > 0, toploc > 0, plus 0 < sensitivity < 1) in `l2_algrunflag`
        # (GEDI Level 2 User Guide V3.0). Its `selected_algorithm` also carries a
        # stale `valid_range` of 1–6 while group 10 is used, so reading it would
        # mask those shots as missing.
        push!(variables, Variable(:l2_algrun, "l2_algrunflag", UInt8))
        return variables
    end
    push!(variables, Variable(:selected_algorithm, "selected_algorithm", UInt8))
    for algorithm in gedi_algorithms(g)
        prefix = "rx_processing_a$algorithm"
        push!(
            variables,
            Variable(Symbol("a", algorithm, "_algrun"), "$prefix/rx_algrunflag", UInt8),
        )
        push!(
            variables,
            Variable(Symbol("a", algorithm, "_zcross"), "$prefix/zcross", Float32),
        )
        push!(
            variables,
            Variable(Symbol("a", algorithm, "_toploc"), "$prefix/toploc", Float32),
        )
    end
    return variables
end

# A sourceless table only needs the shared columns. The algorithm checks come
# from `l2_algrun` (version 3) or from `selected_algorithm` with the per-algorithm
# columns `aN_algrun`, `aN_zcross` and `aN_toploc` (version 2); `_mask` uses
# whichever is present, so tables from either product version validate.
_inputs(::Quality, ::Nothing) = _namevar.(collect(_quality_names))

_nonzero(value) = !ismissing(value) && !iszero(value)
_zero(value) = !ismissing(value) && iszero(value)

function _mask(::Quality, cols)
    rx_assess_quality = Tables.getcolumn(cols, :rx_assess_quality)
    surface = Tables.getcolumn(cols, :surface)
    stale_return = Tables.getcolumn(cols, :stale_return)
    rx_maxamp = Tables.getcolumn(cols, :rx_maxamp)
    sd_corrected = Tables.getcolumn(cols, :sd_corrected)
    degrade = Tables.getcolumn(cols, :degrade)

    names = Tables.columnnames(cols)
    algorithm_ok = if :l2_algrun in names
        BitVector(map(_nonzero, Tables.getcolumn(cols, :l2_algrun)))
    else
        _selected_algorithm_ok(cols, names, length(degrade))
    end

    mask = BitVector(undef, length(degrade))
    @inbounds for i in eachindex(mask)
        mask[i] = algorithm_ok[i] &&
                  _nonzero(rx_assess_quality[i]) &&
                  _nonzero(surface[i]) &&
                  _zero(stale_return[i]) &&
                  !ismissing(rx_maxamp[i]) &&
                  !ismissing(sd_corrected[i]) &&
                  rx_maxamp[i] / sd_corrected[i] >= 8 &&
                  _zero(degrade[i])
    end
    return mask
end

# Version 2: per-algorithm checks for every group that has columns; a row passes
# only if its selected algorithm is one of them.
function _selected_algorithm_ok(cols, names, n)
    :selected_algorithm in names || throw(ArgumentError(
        "GEDI.Quality needs either `l2_algrun` (version 3) or `selected_algorithm` " *
        "with the per-algorithm columns (version 2); filter a table read with " *
        "`table(g)` so they are auto-loaded.",
    ))
    selected_algorithm = Tables.getcolumn(cols, :selected_algorithm)
    ok = falses(n)
    found = false
    for algorithm in 1:_max_algorithm
        algrun = Symbol("a", algorithm, "_algrun")
        zcross = Symbol("a", algorithm, "_zcross")
        toploc = Symbol("a", algorithm, "_toploc")
        (algrun in names && zcross in names && toploc in names) || continue
        found = true
        _check_algorithm!(
            ok,
            selected_algorithm,
            algorithm,
            Tables.getcolumn(cols, algrun),
            Tables.getcolumn(cols, zcross),
            Tables.getcolumn(cols, toploc),
        )
    end
    found || throw(ArgumentError(
        "GEDI.Quality needs the columns `aN_algrun`, `aN_zcross` and `aN_toploc` " *
        "of at least one algorithm setting group N; filter a table read with " *
        "`table(g)` so they are auto-loaded.",
    ))
    return ok
end

# Function barrier: the column types are concrete inside this loop.
function _check_algorithm!(ok, selected_algorithm, algorithm, algrun, zcross, toploc)
    @inbounds for i in eachindex(ok)
        selected = selected_algorithm[i]
        if !ismissing(selected) && selected == algorithm
            ok[i] = _nonzero(algrun[i]) &&
                    !ismissing(zcross[i]) &&
                    zcross[i] > 0 &&
                    !ismissing(toploc[i]) &&
                    toploc[i] > 0
        end
    end
    return ok
end

"""
    Sensitivity([gt=0.9])
    Sensitivity(; gt=0.9)

Filter GEDI L2A rows to `gt < sensitivity <= 1.0`. GEDI sensitivity is stored
on a 0-1 scale; values outside that range and missing values are rejected.
"""
Base.@kwdef struct Sensitivity{T<:Real} <: Filter
    gt::T = 0.9
    function Sensitivity{T}(gt::T) where {T<:Real}
        0 <= gt < 1 ||
            throw(ArgumentError("GEDI sensitivity threshold must satisfy 0 <= gt < 1"))
        return new{T}(gt)
    end
end
Sensitivity(gt::T) where {T<:Real} = Sensitivity{T}(gt)

_inputs(::Sensitivity, g::GEDI_Granule{:GEDI02_A}) = [_var(g, :sensitivity)]
_inputs(::Sensitivity, ::Nothing) = [_namevar(:sensitivity)]

function _mask(op::Sensitivity, cols)
    sensitivity = Tables.getcolumn(cols, :sensitivity)
    mask = BitVector(undef, length(sensitivity))
    @inbounds for i in eachindex(sensitivity)
        value = sensitivity[i]
        mask[i] = !ismissing(value) && op.gt < value <= 1
    end
    return mask
end

end # module GEDI
