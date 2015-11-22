module correlations

using ..operators
using ..timeevolution
using ..metrics
using ..steadystate


function correlation(tspan::Vector{Float64}, rho0::Operator, H::AbstractOperator, J::Vector,
                     op1::AbstractOperator, op2::AbstractOperator;
                     Gamma::Union{Real, Vector, Matrix}=ones(Float64, length(J)),
                     Jdagger::Vector=map(dagger, J),
                     tmp::Operator=deepcopy(rho0),
                     kwargs...)
    exp_values = Complex128[]
    function fout(t, rho)
        push!(exp_values, expect(op1, rho))
    end
    timeevolution.master(tspan, op2*rho0, H, J; Gamma=Gamma, Jdagger=Jdagger,
                        tmp=tmp, fout=fout, kwargs...)
    return exp_values
end


function correlation(rho0::Operator, H::AbstractOperator, J::Vector,
                     op1::AbstractOperator, op2::AbstractOperator;
                     eps::Float64=1e-4, h0=10.,
                     Gamma::Union{Real, Vector, Matrix}=ones(Float64, length(J)),
                     Jdagger::Vector=map(dagger, J),
                     tmp::Operator=deepcopy(rho0),
                     kwargs...)
    op2rho0 = op2*rho0
    tout = Float64[0.]
    exp_values = Complex128[expect(op1, op2rho0)]
    function fout(t, rho)
        push!(tout, t)
        push!(exp_values, expect(op1, rho))
    end
    steadystate.master(H, J; rho0=op2rho0, eps=eps, h0=h0, fout=fout,
                       Gamma=Gamma, Jdagger=Jdagger, tmp=tmp, kwargs...)
    return tout, exp_values
end


function correlationspectrum(omega_samplepoints::Vector{Float64},
                H::AbstractOperator, J::Vector, op::AbstractOperator;
                eps::Float64=1e-4,
                rho_ss::Operator=steadystate.master(H, J; eps=eps),
                kwargs...)
    domega = minimum(diff(omega_samplepoints))
    dt = 2*pi/(omega_samplepoints[end] - omega_samplepoints[1])
    T = 2*pi/domega
    tspan = [0.:dt:T;]
    exp_values = correlation(tspan, rho_ss, H, J, dagger(op), op, kwargs...)
    # dtmin = minimum(diff(tspan))
    # T = tspan[end] - tspan[1]
    # domega = 2*pi/T
    # omega_min = -pi/dtmin
    # omega_max = pi/dtmin
    # omega_samplepoints = Float64[omega_min:domega:omega_max-domega/2;]
    S = Float64[]
    for omega=omega_samplepoints
        y = exp(1im*omega*tspan).*exp_values/pi
        I = 0.im
        for j=1:length(tspan)-1
            I += (tspan[j+1] - tspan[j])*(y[j+1] + y[j])
        end
        I = I/2
        push!(S, real(I))
    end
    return omega_samplepoints, S
end


function correlationspectrum(H::AbstractOperator, J::Vector, op::AbstractOperator;
                eps::Float64=1e-4, h0=10.,
                rho_ss::Operator=steadystate.master(H, J; eps=eps),
                kwargs...)
    tspan, exp_values = correlation(rho_ss, H, J, dagger(op), op, eps=eps, h0=h0, kwargs...)
    dtmin = minimum(diff(tspan))
    T = tspan[end] - tspan[1]
    tspan = Float64[0.:dtmin:T;]
    return correlationspectrum(tspan, H, J, op; eps=eps, rho_ss=rho_ss, kwargs...)
    # domega = 1./T
    # omega_min = -pi/dtmin
    # omega_max = pi/dtmin
    # omega_samplepoints = Float64[omega_min:domega:omega_max;]
    # S = Float64[]
    # for omega=omega_samplepoints
    #     y = exp(1im*omega*tspan).*exp_values/pi
    #     I = 0.im
    #     for j=1:length(tspan)-1
    #         I += (tspan[j+1] - tspan[j])*(y[j+1] + y[j])
    #     end
    #     I = I/2
    #     push!(S, real(I))
    # end
    # return omega_samplepoints, S
end

end # module