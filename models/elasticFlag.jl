using Gridap
using Gridap.Io
using GridapGmsh

model = GmshDiscreteModel("elasticFlag.msh")

writevtk(model, "outputs/$(basename(@__FILE__))_elasticFlag");

fn = "elasticFlag.json"
to_json_file(model, fn)
