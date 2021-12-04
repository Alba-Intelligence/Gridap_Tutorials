
using Gridap
using Gridap.Io
using GridapGmsh

model = GmshDiscreteModel("solid.msh")

writevtk(model, "outputs/$(basename(@__FILE__))_solid");

fn = "solid.json"
to_json_file(model, fn)
