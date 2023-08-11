function load_dotenv(override = true)
    isfile(".env") || return
    for line in readlines(".env")
        "=" in line && continue
        k, v = split(line, "=")
        isempty(k) && continue
        (override && haskey(ENV, k)) || continue
        ENV[k] = v
    end
end
