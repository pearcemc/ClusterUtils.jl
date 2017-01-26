import Base.del_client
export del_client

# PATCHES FOR STUFF WHAT EFFECTS CLUSTER COMPUTING

# Representation of SharedArray that works for remotely hosted data. 
function getrepresentation(S)
    buf = IOBuffer()
    td = TextDisplay(buf)
    Base.Multimedia.display(td, S)
    str = takebuf_string(buf)
    return str
end

function Base.display(S::SharedArray)
    validpid = minimum(S.pids)
    repr = @fetchfrom validpid getrepresentation(S)
    print_with_color(:bold, repr)
end

#workarounds for #14445 - basically doing remotecall can break garbage collection

if VERSION < v"0.5-"

function del_client(pg, id, client)
# As a workaround to issue https://github.com/JuliaLang/julia/issues/14445
# the dict/set updates are executed asynchronously so that they do
# not occur in the midst of a gc. The `@async` prefix must be removed once
# 14445 is fixed.
    @async begin
        rv = get(pg.refs, id, false)
        if rv != false
            delete!(rv.clientset, client)
            if isempty(rv.clientset)
                delete!(pg.refs, id)
            end
        end
    end
    nothing
end

end



