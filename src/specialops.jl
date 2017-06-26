"""
An LinDiagOp which is stored explicitly as all of its diagonal coefficients in
the basis in which it's diagonal.
"""
struct FullDiagOp{F<:Field,P,S,B} <: LinDiagOp{P,S,B}
    f::F
    FullDiagOp(f::F) where {P,S,B,F<:Field{P,S,B}} = new{F,P,S,B}(f)
end
for op=(:*,:\)
    @eval ($op)(O::FullDiagOp{F}, f::F) where {F} = $(Symbol(:.,op))(O.f,f)
end
*(f::Field,O::FullDiagOp) = O*f
sqrtm(f::FullDiagOp) = sqrt.(f)
simulate(Σ::FullDiagOp{F}) where {F} = sqrtm(Σ) .* F(white_noise(F))
broadcast_data(::Type{F}, op::FullDiagOp{F}) where {F} = broadcast_data(F,op.f)
containertype(op::FullDiagOp) = containertype(op.f)
literal_pow(^,op::FullDiagOp,::Type{Val{-1}}) = inv(op)
inv(op::FullDiagOp) = FullDiagOp(1./op.f)
ctranspose(f::FullDiagOp) = f



# Operators used to take derivatives
abstract type DerivBasis <: Basislike end
const Ð = DerivBasis
struct ∂{s} <: LinDiagOp{Pix,Spin,DerivBasis} end
const ∂x,∂y= ∂{:x}(),∂{:y}()
const ∇ = @SVector [∂x,∂y]
const ∇ᵀ = RowVector(∇)
*(∂::∂, f::Field) = ∂ .* Ð(f)
function gradhess(f)
    (∂xf,∂yf)=∇*Ð(f)
    ∂xyf = ∂x*∂yf
    @SVector([∂xf,∂yf]), @SMatrix([∂x*∂xf ∂xyf; ∂xyf ∂y*∂yf])
end
shortname(::Type{∂{s}}) where {s} = "∂$s"
struct ∇²Op <: LinDiagOp{Pix,Spin,DerivBasis} end
const ∇² = ∇²Op()
*(∇²::∇²Op, f::Field) = ∇² .* Ð(f)

"""
An Op which applies some arbitrary function to its argument.
Transpose and/or inverse operations which are not specified will return an error.
"""
@with_kw struct FuncOp <: LinOp{Pix,Spin,Basis}
    op   = nothing
    opᴴ  = nothing
    op⁻¹ = nothing
    op⁻ᴴ = nothing
end
SymmetricFuncOp(;op=nothing, op⁻¹=nothing) = FuncOp(op,op,op⁻¹,op⁻¹)
@∷ *(op::FuncOp, f::Field) = op.op   != nothing ? op.op(f)   : error("op*f not implemented")
@∷ *(f::Field, op::FuncOp) = op.opᴴ  != nothing ? op.opᴴ(f)  : error("f*op not implemented")
@∷ \(op::FuncOp, f::Field) = op.op⁻¹ != nothing ? op.op⁻¹(f) : error("op\\f not implemented")
ctranspose(op::FuncOp) = FuncOp(op.opᴴ,op.op,op.op⁻ᴴ,op.op⁻¹)
const IdentityOp = FuncOp(repeated(identity,4)...)
literal_pow(^,op::FuncOp,::Type{Val{-1}}) = FuncOp(op.op⁻¹,op.op⁻ᴴ,op.op,op.opᴴ)


# band passes
struct BandPassOp{T<:Vector} <: LinDiagOp{Pix,Spin,DerivBasis}
    ℓ::T
    Wℓ::T
end
HP(ℓ,Δℓ=50) = BandPassOp(collect(0.:10000), [zeros(ℓ-Δℓ); @.((cos(linspace(π,0,2Δℓ))+1)/2); ones(10001-ℓ-Δℓ)])
LP(ℓ,Δℓ=50) = BandPassOp(collect(0.:(ℓ+Δℓ-1)), [ones(ℓ-Δℓ); @.(cos(linspace(0,π,2Δℓ))+1)/2])
*(op::BandPassOp,f::Field) = op .* Ð(f)
(::Type{FullDiagOp{F}})(b::BandPassOp) where {F<:Field} = FullDiagOp(F(broadcast_data(F,b)...))

""" An Op which turns all NaN's to zero """
const Squash = SymmetricFuncOp(op=x->broadcast(nan2zero,x))