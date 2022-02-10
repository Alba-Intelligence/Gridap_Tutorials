# ## Introduction

# In this tutorial we will learn how to use [`GridapODEs.jl`](https://github.com/gridap/GridapODEs.jl) to solve the transient PDEs by solving the *heat equation*, equivalent to the transient Poisson equation.

# We will focus on the time discretization on the equations, assuming that the reader is familiar with the spatial Finite Element discretization given in [tutorial 1](https://gridap.github.io/Tutorials/stable/pages/t001_poisson/).

# ## Problem statement

# We solve the heat equation in a 2-dimensional domain defined by a square with Homogenous Dirichlet boundaries, $\Gamma_D$. We consider a time-dependent conductivity $\kappa(t)=1.0 + 0.95\sin(2\pi t)$, a time-dependent volumetric forcing term $f(t) = \sin(\pi t)$ and a constant Homogenous boundary condition $g = 0.0$. The initial solution is $u(x,0) = u_0 = 0$. With these definitions, the strong form of the problem reads:

# ```math
# \left\lbrace
# \begin{aligned}
# \frac{\partial u(t)}{\partial t} -\kappa(t)\Delta u(t) = f(t)  \ &\text{in} \ \Omega,\\
# u(t) = 0 \ &\text{on}\ \Gamma_{\rm D},\\
# u(0) = 0 \ &\text{in}\ \Omega\\
# \end{aligned}
# \right.
# ```

# The weak form of the problem will read: find $u(t)\in U_g(t)$ such that

# ```math
# m(t,u,v) + a(t,u,v) = b(t,v)\quad \forall v\in \ V
# ```

# Note that $U_g(t)$ is a transient FE space, in the sense that Dirichlet boundary value of functions in $U_g$ can change in time. The definition of $m(u,v)$, $a(u,v)$ and $b(v)$ is as follows:

# ```math
# \begin{aligned}
# m(t,u,v) = \int_\Omega v\frac{\partial u}{\partial t} d\Omega, \\
# a(t,u,v) = \int_\Omega \kappa(t) \nalba v\cdot \nabla u d\Omega, \\
# b(t,v) = \int_\Omega v\ f(t) d\Omega
# \end{aligned}
# ```

# ## Discrete model and Triangulation

# Let us load the two packages that we will use in this tutorial `Gridap` and `GridapODEs`.
using Gridap
using GridapODEs
using GridapODEs.ODETools
using GridapODEs.TransientFETools

# Without going into the details we define the `DiscreteModel` and the `Triangulation`, as it is detailed in [tutorial 2](https://gridap.github.io/Tutorials/stable/pages/t002_validation/).


𝒯 = CartesianDiscreteModel((0,1,0,1),(20,20))
Ω = Interior(𝒯)
dΩ = Measure(Ω,2)

# ## FE space

# In this tutorial we will use linear Lagrangian Finite Elements.
refFE = ReferenceFE(lagrangian,Float64,1)

# The space of test functions is constant in time and is defined in steady problems:
V = TestFESpace(𝒯,refFE,dirichlet_tags="boundary")

# The trial space is now a `TransientTrialFESpace`, wich is constructed from a `TestFESpace` and a function (or vector of functions) for the Dirichlet boundary condition/s. In that case, the boundary condition function is a time-independent constant, but it could also be a time-dependent field depending on the coordinates $x$ and time $t$.
g(x,t::Real) = 0.0
g(t::Real) = x -> g(x,t)
U = TransientTrialFESpace(V,g)

# ## Weak form

# The weak form of the problem follows the same structure as other `Gridap` tutorials, where we define the bilinear and linear forms to define the `FEOperator`. In this case we need to deal with time-dependent quantities and with the presence of time derivatives. The former is handled by passing the time, $t$, as an additional argument to the form, i.e. $a(t,u,v)$. The later is defined using the time derivative operator `∂t`.

# The most general way of constructing a transient FE operator is by using the `TransientFEOperator` function, which receives a residual, a jacobian with respect to the unknown and a jacobian with respect to the time derivative.
κ(t) = 1.0 + 0.95*sin(2π*t)
f(t) = sin(π*t)
res(t,u,v) = ∫( ∂t(u)*v + κ(t)*(∇(u)⋅∇(v)) - f(t)*v )dΩ
jac(t,u,du,v) = ∫( κ(t)*(∇(du)⋅∇(v)) )dΩ
jac_t(t,u,duₜ,v) = ∫( duₜ*v )dΩ
op = TransientFEOperator(res,jac,jac_t,U,V)

# We can also take advantage of automatic differentitation techniques and use the `TransientFEOperator` function sending only the residual.
op_AD = TransientFEOperator(res,U,V)

# Alternatively, we can exploit the fact that the problem is linear and use the transient Affine FE operator signature `TransientAffineFEOperator`. In that case, we send a form for the mass contribution, $m$, a form for the stiffness contribution, $a$, and the forcing term, $b$.
m(t,u,v) = ∫( u*v )dΩ
a(t,u,v) = ∫( κ(t)*(∇(u)⋅∇(v)) )dΩ
b(t,v) = ∫( f(t)*v )dΩ
op_Af = TransientAffineFEOperator(m,a,b,U,V)

# ### Alternative FE operator definitions

# For time-dependent problems with constant coefficients, which is not the case of this tutorial, one could use the optimized operator `TransientConstantMatrixFEOperator`, which assumes that the matrix contributions ($m$ and $a$) are time-independent. That is:
m₀(u,v) = ∫( u*v )dΩ
a₀(u,v) = ∫( κ(0.0)*(∇(u)⋅∇(v)) )dΩ
op_CM = TransientConstantMatrixFEOperator(m,a,b,U,V)

# Going further, if we had a problem with constant forcing term, i.e. constant force and constant boundary conditions, we could have used the `TransientConstantFEOperator`. In that case the linear form is also time-independent.
b₀(v) = ∫( f(0.0)*v )dΩ
op_C = TransientConstantFEOperator(m,a,b,U,V)

# ## Transient solver

# Once we have the FE operator defined, we proceed with the definition of the transient solver. First, we define a linear solver to be used at each time step. Here we use the `LUSolver`, but other choices could be made.
linear_solver = LUSolver()

# Then, we define the ODE solver. That is, the scheme that will be used for the time integration. In this tutorial we use the `ThetaMethod` with $\theta = 0.5$, resulting in a 2nd order scheme. The `ThetaMethod` function receives the linear solver, the time step size $\Delta t$ (constant) and the value of $\theta $.
Δt = 0.05
θ = 0.5
ode_solver = ThetaMethod(linear_solver,Δt,θ)

# Finally, we define the solution using the `solve` function, giving the ODE solver, the FE operator, an initial solution, an initial time and a final time. To construct the initial condition we interpolate the initial value (in that case a constant value of 0.0) into the FE space $U(t)$ at $t=0.0$.
u₀ = interpolate_everywhere(0.0,U(0.0))
t₀ = 0.0
T = 10.0
uₕₜ = solve(ode_solver,op,u₀,t₀,T)

# ## Postprocessing

# We should highlight that `uₕₜ` is just an iterable function and the results at each time steps are only computed when iterating over it. We can post-process the results and generate the corresponding `vtk` files using the `createpvd` and `createvtk` functions. The former will create a `.pvd` file with the collection of `.vtu` files saved at each time step by `createvtk`. This can be done as follows:
createpvd("poisson_transient_solution") do pvd
  for (uₕ,t) in uₕₜ
    pvd[t] = createvtk(Ω,"poisson_transient_solution_$t"*".vtu",cellfields=["u"=>uₕ])
  end
end

# ![](../assets/poisson_transient/poisson_transient.gif)
