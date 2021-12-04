
using Gridap
using Gridap.Io
using GridapGmsh

model = GmshDiscreteModel("model.msh")

writevtk(model, "outputs/$(basename(@__FILE__))_model");

fn = "model.json"
to_json_file(model, fn)
