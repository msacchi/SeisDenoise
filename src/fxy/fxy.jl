"""
   fxy prediction filter, op is the 2D filter, filter size is (2L+1) \times (2L+1)
   data one frequency slice, adj = false: do 2D convolution; adj = true ; do 2D crosscorrelation
"""
function fxy_convolution(op::Matrix{Complex{Tv}}, adj; data::Matrix{Complex{Tv}}=1, L=1) where {Tv<:Float64}

    # size of input data
    (n1, n2) = size(data)

    # forward operator
    if (adj==false)

       # allocate memory for the output
       dout = zeros(Complex{Tv}, n1-2*L, n2-2*L)

       # set the center of the filter equal to zero
       op[L+1,L+1] = 0. + im*0.

       # convolution for the center part
       for i2 = L+1 : n2-L
           k2 = i2 - L

           for i1 = L+1 : n1-L
               k1 = i1 - L

               # one element of output
               for j2 = -L : L
                   for j1 = -L : L
                       dout[k1,k2] += data[i1+j1,i2+j2] * op[L+1+j1,L+1+j2]
                   end
               end
           end
       end

   # adjoint operator
   elseif (adj=true)

      # allocate memory for the output
      dout = zeros(Complex{Float64},2*L+1,2*L+1)

      for j2 = -L : L
          k2 = L+1+j2

          for j1 = -L : L
              k1 = L+1+j1

              for i2 = L+1 : n2-L
                  for i1 = L+1 : n1-L
                      dout[k1,k2] += conj(data[i1+j1,i2+j2]) * op[i1-L,i2-L]
                  end
              end
          end
      end

      # set the center equal to 0
      dout[L+1, L+1] = 0.0 + im*0.0
   end

   return dout
end

"""
   considering the boundary part
"""
function fxy_test(op::Matrix{Complex{Tv}}, adj; data::Matrix{Complex{Tv}}=1, L=1) where {Tv<:Float64}

    # size of input data
    (n1, n2) = size(data)

    # forward operator
    if (adj==false)

       # allocate memory for the output
       dout = zeros(Complex{Tv}, n1, n2)

       # set the center of the filter equal to zero
       op[L+1,L+1] = 0. + im*0.

       # convolution for the center part
       for i2 = 1 : n2
           f2_lower = i2 - L; f2_lower < 1  ? f2_lower : 1
           f2_upper = i2 + L; f2_upper > n2 ? f2_upper : n2
           j2_lower = f2_lower - i2
           j2_upper = f2_upper - i2

           for i1 = 1 : n1
               f1_lower = i1 - L; f1_lower < 1  ? f1_lower : 1
               f1_upper = i1 + L; f1_upper > n1 ? f1_upper : n1
               j1_lower = f1_lower - i1
               j1_upper = f1_upper - i1

               # one element of output
               for j2 = j2_lower : j2_upper
                   for j1 = j1_lower : j1_upper
                       dout[i1,i2] += data[i1+j1,i2+j2] * op[L+1+j1,L+1+j2]
                   end
               end
           end
       end

   # adjoint operator
   elseif (adj=true)

      # allocate memory for the output
      dout = zeros(Complex{Float64},2*L+1,2*L+1)

      for i2 = 1 : n2
          f2_lower = i2 - L; f2_lower < 1  ? f2_lower : 1
          f2_upper = i2 + L; f2_upper > n2 ? f2_upper : n2
          j2_lower = f2_lower - i2
          j2_upper = f2_upper - i2

          for i1 = 1 : n1
              f1_lower = i1 - L; f1_lower < 1  ? f1_lower : 1
              f1_upper = i1 + L; f1_upper > n1 ? f1_upper : n1
              j1_lower = f1_lower - i1
              j1_upper = f1_upper - i1

              # one element of output
              for j2 = j2_lower : j2_upper
                  k2 = j2+L+1

                  for j1 = j1_lower : j1_upper
                      k1 = j1+L+1

                      dout[k1,k2] += conj(data[i1+j1,i2+j2]) * op[i1,i2]
                  end
              end
          end
      end

      # set the center equal to 0
      dout[L+1, L+1] = 0.0 + im*0.0
   end

   return dout
end

"""
   forward and adjoint of concatenated linear operators
"""
function linear_operators(din, operators, parameters; adj=false)

    # number of linear operator
    num_op = length(operators)

    # forward
    if adj == false
       m = copy(din)
       d = []

       # loop over forward operators
       for j = 1 : num_op

           op = operators[j]
           d  = op(m, false; parameters[j]...)

           # prepare for the next linear operator
           m  = copy(d)
       end
       return d

    # adjoint
    elseif adj == true
       d = copy(din)
       m = []

       # loop over adjoint operators
       for j = num_op : -1 : 1

           op = operators[j]
           m  = op(d, true; parameters[j]...)

           # prepare for the next linear operator
           d = copy(m)
       end
       return m
    end
end

"""
    ConjugateGradients(d,operators,parameters;<keyword arguments>)
Conjugate Gradients following Algorithm 2 from Scales, 1987.
"""



function CGLS(d, operators, parameters; Niter=10, mu=0, tol=1.0e-15)

    cost = Float64[]
    r = copy(d)
    g = linear_operators(r, operators, parameters; adj=true)
    m = zero(g)
    s = copy(g)

    gamma   = real(dot(g, g))
    gamma00 = gamma
    cost0   = real(dot(r, r))
    push!(cost, 1.0)

    for iter = 1 : Niter
	      t     = linear_operators(s, operators, parameters; adj=false)
	      delta = real(dot(t, t) + mu * dot(s, s))

        if delta <= tol
           println("delta reached tolerance, ending at iteration $iter")
	         break
	      end

	      alpha = gamma / delta
	      m = m + alpha * s
	      r = r - alpha * t

	      g = linear_operators(r, operators, parameters; adj=true)
	      g = g - mu * m
	      gamma0 = copy(gamma)
	      gamma  = real(dot(g, g))

        cost1 = dot(r, r) + mu * dot(m, m)
        push!(cost, real(cost1/cost0))

	      beta = gamma / gamma0
	      s    = beta * s + g

	      if (sqrt(gamma) <= sqrt(gamma00) * tol)
	         println("tolerance reached, ending at iteration $iter")
	         break;
	      end
    end

    return m, cost
end

"""
   fxy prediction filter
"""
function fxy_prediction(cube::Array{Tv,3}; dt=0.002, L=5, flow=0.0, fhigh=80.0) where {Tv<:AbstractFloat}

    dt = convert(Tv, dt)
    (nt, n1, n2) = size(cube)

    # padding zeros to data cube
    nf = nextpow(2, nt)
    nyq= floor(Int64, nf/2) + 1
    df = 1.0 / dt / nf

    # frequency index
    iw_lower = floor(Int64, flow  / dt) + 1
    iw_upper = floor(Int64, fhigh / dt) + 1
    iw_lower = iw_lower < 2   ? 2   : iw_lower
    iw_upper = iw_upper > nyq ? nyq : iw_upper

    # padding zeros fft
    cube = vcat(cube, zeros(Tv, nf-nt, n1, n2))
    cube = fft(cube, 1)

    # allocate space for the filtered data
    dout = copy(cube)

    # tmporary data
    b = zeros(Complex{Tv}, n1-2*L, n2-2*L)
    d = zeros(Complex{Tv}, n1, n2)

    # loop over frequency slice
    for iw = iw_lower : iw_upper
        b .= cube[iw, L+1:n1-L, L+1:n2-L]
        d .= cube[iw, :, :]

        # estimate filter
        (f, cost) = CGLS(b, [fxy_convolution], [Dict(:data=>d, :L=>L)]; Niter=15, mu=.001, tol=1.0e-8);

        # apply estimated filter
        b = fxy_convolution(f, false; data=d, L=L)

        # replace with the filtered data
        dout[iw, L+1:n1-L, L+1:n2-L] .= b
        dout[nf-iw+2,:,:] .= conj.(dout[iw, :, :])

        println("$iw")
    end

    dout = real(ifft(dout, 1))
    return dout[1:nt, :, :]

end

using  SeisPlot, FFTW, LinearAlgebra, SeisProcessing

dt = 4.0/1000.
d = SeisLinearEvents(;ot=0.0,dt=dt, nt=200, ox1=0.0, dx1=10.0,
                      nx1=80, ox2=0.0, dx2=10.0, nx2=83, ox3=0.0, dx3=10.0,
                      nx3=1, ox4=0.0, dx4=10.0, nx4=1, tau=[.4,.5],
                      p1=[0.0001,-0.0003],p2=[0.0001,-0.0003],p3=[0.,0],p4=[0.,0.],
                      amp=[1.0,-1.0], f0=24.0);

din  = SeisAddNoise(d,.5);

dout = fxy_prediction(din; dt=dt, L=4, flow=0.0, fhigh=60.0)

SeisPlotTX(d[:,:,10], style="wiggles", xcur=2)
SeisPlotTX(din[:,:,10], style="wiggles", xcur=2)
SeisPlotTX(dout[:,:,10], style="wiggles", xcur=2)
SeisPlotTX(dout[:,:,10] - din[:,:,10], style="wiggles", xcur=2)







data = rand(Complex{Float64}, 111, 121);
L = 5;
m = rand(Complex{Float64}, 2*L+1, 2*L+1);
operators = [fxy_test]
parameters= [Dict(:data=>data, :L=>L)]
d = linear_operators(m, operators, parameters; adj=false)

d1 = rand(Complex{Float64}, 101, 111);
m1 = linear_operators(d1, operators, parameters; adj=true)
dot(m, m1);
dot(d, d1);
