# Build the GEDI L2A version 3 test artifact: two beams of one granule, cut to the
# shots inside a 1° tile, with every dataset and attribute of those beams.
#
#   julia --project=. test/make_gedi_v3_subset.jl <full V003 granule> <output folder>
#
# The test artifact (release v0.4.0 of evetion/SpaceLiDAR-artifacts) was made from
# GEDI02_A_2020257225350_O09946_02_T08506_02_004_02_V003.h5, beams BEAM0000 (coverage)
# and BEAM0101 (full power), tile 52–53°N, 6–7°E (the Netherlands).
using HDF5

const BEAMS = ("BEAM0000", "BEAM0101")
const LAT = (52.0, 53.0)
const LON = (6.0, 7.0)
# dimension-scale bookkeeping refers to objects in the source file; it is rebuilt below
const SKIP_ATTRS = ("DIMENSION_LIST", "REFERENCE_LIST", "CLASS", "NAME")

function copy_attributes(src, dst)
    for name in keys(attributes(src))
        name in SKIP_ATTRS && continue
        attributes(dst)[name] = read(attributes(src)[name])
    end
end

function write_data(dst, name, data)
    if data isa AbstractArray && length(data) > 64 && isbitstype(eltype(data))
        chunk = ntuple(i -> i == ndims(data) ? min(size(data, i), 1024) : size(data, i), ndims(data))
        dst[name, chunk = chunk, deflate = 4] = data
    else
        dst[name] = data
    end
end

function copy_group(src, dst, idx, nshots)
    copy_attributes(src, dst)
    for name in keys(src)
        obj = src[name]
        if obj isa HDF5.Group
            copy_group(obj, create_group(dst, name), idx, nshots)
        else
            data = read(obj)
            if data isa AbstractArray && !isempty(data) && size(data, ndims(data)) == nshots
                data = selectdim(data, ndims(data), idx) |> collect
            end
            write_data(dst, name, data)
            copy_attributes(obj, dst[name])
        end
        close(obj)
    end
end

# Attach delta_time as dimension scale of the shot axis (HDF5 axis 0), as in the source.
function attach_scales(group, nsub)
    scale = group["delta_time"]
    HDF5.API.h5ds_set_scale(scale, "delta_time")
    function walk(g)
        for name in keys(g)
            obj = g[name]
            if obj isa HDF5.Group
                walk(obj)
            elseif HDF5.name(obj) != HDF5.name(scale) && !isempty(size(obj)) && last(size(obj)) == nsub
                HDF5.API.h5ds_attach_scale(obj, scale, 0)
            end
            close(obj)
        end
    end
    walk(group)
    close(scale)
end

function main(source, folder)
    mkpath(folder)
    target = joinpath(folder, basename(source))
    h5open(source, "r") do src
        h5open(target, "w") do dst
            copy_attributes(src, dst)
            copy_group(src["METADATA"], create_group(dst, "METADATA"), Int[], -1)
            for beam in BEAMS
                lat = read(src[beam]["lat_lowestmode"])
                lon = read(src[beam]["lon_lowestmode"])
                idx = findall((LAT[1] .<= lat .< LAT[2]) .& (LON[1] .<= lon .< LON[2]))
                copy_group(src[beam], create_group(dst, beam), idx, length(lat))
                attach_scales(dst[beam], length(idx))
                println("$beam: kept $(length(idx)) of $(length(lat)) shots")
            end
        end
    end
    println("wrote $target ($(round(filesize(target) / 1e6; digits = 1)) MB)")
end

main(ARGS[1], ARGS[2])
