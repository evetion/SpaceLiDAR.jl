using SpaceLiDAR
using Test
using Aqua
using ExplicitImports
using Dates
using Distances
import Downloads
using Random
using DataFrames
using Tables
using Proj
using Documenter
using Extents
using GeoInterface
using CategoricalArrays
using DataAPI
using GeoFormatTypes

const rng = MersenneTwister(54321)
const SL = SpaceLiDAR

@static if Sys.isapple()
    using MozillaCACerts_jll
    ENV["CURL_CA_BUNDLE"] = MozillaCACerts_jll.cacert
end

# ensure test data is present
testdir = @__DIR__
datadir = joinpath(testdir, "data")
isdir(datadir) || mkdir(datadir)
SpaceLiDAR.load_dotenv()  # get earthdata credentials for local testing

function download_artifact(version, source_filename)
    local_path = joinpath(datadir, source_filename)
    url = "https://github.com/evetion/SpaceLiDAR-artifacts/releases/download/v$version/$source_filename"
    isfile(local_path) || Downloads.download(url, local_path)
    return local_path
end

ATL03_fn = download_artifact(v"0.3", "ATL03_20201121151145_08920913_006_01.h5")
ATL06_fn = download_artifact(v"0.3", "ATL06_20220404104324_01881512_006_02.h5")
ATL08_fn = download_artifact(v"0.3", "ATL08_20201121151145_08920913_006_01.h5")
ATL12_fn = download_artifact(v"0.3", "ATL12_20220404110409_01891501_006_02.h5")
GEDI02_fn = download_artifact(v"0.1", "GEDI02_A_2019242104318_O04046_01_T02343_02_003_02_V002.h5")
GLAH14_fn = download_artifact(v"0.1", "GLAH14_634_1102_001_0071_0_01_0001.H5")
GLAH06_fn = download_artifact(v"0.1", "GLAH06_634_2131_002_0084_4_01_0001.H5")

empty_bbox = (min_x = 0.0, min_y = 0.0, max_x = 0.0, max_y = 0.0)
empty_extent = convert(Extent, empty_bbox)

@testset "SpaceLiDAR.jl" begin
    @testset "Aqua" begin
        Aqua.test_all(
            SpaceLiDAR;
            deps_compat = (; check_extras = false),
            piracies = (; treat_as_own = [Extents.Extent]),
        )
    end
    @testset "ExplicitImports" begin
        # The public-ness and ownership checks are disabled because the package
        # necessarily relies on non-public / re-exported API of its dependencies
        # (e.g. HDF5.API low-level calls, Tables/DataAPI interface functions,
        # Proj and TerminalMenus internals, TableOperations.joinpartitions,
        # AWSS3/Downloads.Curl re-exports). The remaining four checks (implicit
        # imports, stale imports, explicit-import ownership, self-qualified
        # accesses) are enforced.
        test_explicit_imports(
            SpaceLiDAR;
            all_explicit_imports_are_public = false,
            all_qualified_accesses_via_owners = false,
            all_qualified_accesses_are_public = false,
        )
    end
    include("sl.jl")
    include("h5table.jl")
end
