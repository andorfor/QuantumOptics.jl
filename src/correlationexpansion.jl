module correlationexpansion

using Combinatorics, Iterators
using ..bases
# using ..states
using ..operators
# using ..operators_lazy
# using ..ode_dopri

# import Base: *, full
# import ..operators

typealias Mask{N} NTuple{N, Bool}

indices2mask(N::Int, indices::Vector{Int}) = Mask(tuple([(i in indices) for i=1:N]...))
mask2indices{N}(mask::Mask{N}) = Int[i for i=1:N if mask[i]]

complement(N::Int, indices::Vector{Int}) = Int[i for i=1:N if i ∉ indices]
complement{N}(mask::Mask{N}) = tuple([! x for x in mask]...)

correlationindices(N::Int, order::Int) = Set(combinations(1:N, order))
correlationmasks(N::Int, order::Int) = Set(indices2mask(N, indices) for indices in
        correlationindices(N, order))
correlationmasks{N}(S::Set{Mask{N}}, order::Int) = Set(s for s in S if sum(s)==order)
subcorrelationmasks{N}(mask::Mask{N}) = Set(indices2mask(N, indices) for indices in
        chain([combinations(mask2indices(mask), k) for k=2:sum(mask)-1]...))


"""
An operator including only certain correlations.

operators
    A tuple containing the reduced density matrix of each subsystem.
correlations
    A (mask->operator) dict. A mask is a tuple containing booleans which
    indicate if the corresponding subsystem is included in the correlation.
    The operator is the correlation between the specified subsystems.
"""
type ApproximateOperator{N} <: Operator
    basis_l::CompositeBasis
    basis_r::CompositeBasis
    operators::NTuple{N, Operator}
    correlations::Dict{Mask{N}, Operator}

    function ApproximateOperator{N}(basis_l::CompositeBasis, basis_r::CompositeBasis,
                operators::NTuple{N, DenseOperator},
                correlations::Dict{Mask{N}, DenseOperator})
        @assert N == length(basis_l.bases) == length(basis_r.bases)
        for i=1:N
            @assert operators[i].basis_l == basis_l.bases[i]
            @assert operators[i].basis_r == basis_r.bases[i]
        end
        for (mask, op) in correlations
            @assert sum(mask) > 1
            @assert op.basis_l == tensor(basis_l.bases[[mask...]]...)
            @assert op.basis_r == tensor(basis_r.bases[[mask...]]...)
        end
        new(basis_l, basis_r, operators, correlations)
    end
end

function ApproximateOperator{N}(basis_l::CompositeBasis, basis_r::CompositeBasis, S::Set{Mask{N}})
    operators = ([DenseOperator(basis_l.bases[i], basis_r.bases[i]) for i=1:N]...)
    correlations = Dict{Mask{N}, DenseOperator}()
    for mask in S
        @assert sum(mask) > 1
        correlations[mask] = tensor(operators[[mask...]]...)
    end
    ApproximateOperator{N}(basis_l, basis_r, operators, correlations)
end

ApproximateOperator{N}(basis::CompositeBasis, S::Set{Mask{N}}) = ApproximateOperator(basis, basis, S)


"""
Tensor product of a correlation and the density operators of the other subsystems.

Arguments
---------
operators
    Tuple containing the reduced density operators of each subsystem.
mask
    A tuple containing booleans specifying if the n-th subsystem is included
    in the correlation.
correlation
    Correlation operator for the subsystems specified by the given mask.
"""
function embedcorrelation{N}(operators::NTuple{N, DenseOperator}, mask::Mask{N},
            correlation::DenseOperator)
    # Product density operator of all subsystems not included in the correlation.
    if sum(mask) == N
        return correlation
    end
    ρ = tensor(operators[[complement(mask)...]]...)
    op = correlation ⊗ ρ # Subsystems are now in wrong order
    perm = sortperm([mask2indices(mask); mask2indices(complement(mask))])
    permutesystems(op, perm)
end

"""
Calculate the correlation of the subsystems specified by the given index mask.

Arguments
---------
rho
    Density operator of the total system.
mask
    A tuple containing booleans specifying if the n-th subsystem is included
    in the correlation.

Optional Arguments
------------------
operators
    A tuple containing the reduced density operators of the single subsystems.
subcorrelations
    A (mask->operator) dictionary storing already calculated correlations.
"""
function correlation{N}(rho::DenseOperator, mask::Mask{N};
            operators::NTuple{N, DenseOperator}=([ptrace(rho, complement(N, [i]))
                                                  for i in 1:N]...),
            subcorrelations::Dict{Mask{N}, DenseOperator}=Dict())
    # Check if this correlation was already calculated.
    if mask in keys(subcorrelations)
        return subcorrelations[mask]
    end
    order = sum(mask)
    σ = ptrace(rho, mask2indices(complement(mask)))
    σ -= tensor(operators[[mask...]]...)
    for submask in subcorrelationmasks(mask)
        subcorrelation = correlation(rho, submask;
                                     operators=operators,
                                     subcorrelations=subcorrelations)
        σ -= embedcorrelation((operators[[mask...]]...), submask[[mask...]], subcorrelation)
    end
    subcorrelations[mask] = σ
    σ
end

correlation{N}(rho::ApproximateOperator{N}, mask::Mask{N}) = rho.correlations[mask]


"""
Approximate a density operator by including only certain correlations.

Arguments
---------
rho
    The density operator that should be approximated.
masks
    A set containing an index mask for every correlation that should be
    included. A index mask is a tuple consisting of booleans which indicate
    if the n-th subsystem is included in the correlation.
"""
function approximate{N}(rho::DenseOperator, masks::Set{Mask{N}})
    operators = ([ptrace(rho, complement(N, [i])) for i in 1:N]...)
    subcorrelations = Dict{Mask{N}, DenseOperator}() # Dictionary to store intermediate results
    correlations = Dict{Mask{N}, DenseOperator}()
    for mask in masks
        correlations[mask] = correlation(rho, mask;
                                         operators=operators,
                                         subcorrelations=subcorrelations)
    end
    ApproximateOperator{N}(rho.basis_l, rho.basis_r, operators, correlations)
end


function full{N}(rho::ApproximateOperator{N})
    result = tensor(rho.operators...)
    for (mask, correlation) in rho.correlations
        result += embedcorrelation(rho.operators, mask, correlation)
    end
    result
end

end