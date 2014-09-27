!> This is the main driving routine of the nested sampling algorithm
program main

    ! ~~~~~~~ Loaded Modules ~~~~~~~

    use priors_module
    use settings_module,        only: program_settings,allocate_indices
    use random_module,          only: initialise_random, deinitialise_random
 
    use chordal_module,         only: SliceSampling, SliceSampling_Graded, &
                                      HitAndRun, Adaptive_Parallel, &
                                      no_processing, get_live_coordinates
    use evidence_module,        only: KeetonEvidence
    use example_likelihoods
    use feedback_module
#ifdef MPI
    use mpi_module
    use nested_sampling_parallel_module, only: NestedSamplingP
#endif
    use nested_sampling_linear_module,   only: NestedSamplingL

    ! ~~~~~~~ Local Variable Declaration ~~~~~~~
    implicit none

    ! Output of the program
    ! 1) log(evidence)
    ! 2) error(log(evidence))
    ! 3) ndead
    ! 4) number of likelihood calls
    double precision, dimension(5) :: output_info

    type(program_settings)    :: settings  ! The program settings 
    type(prior), dimension(1) :: priors

    pointer loglikelihood
    double precision :: loglike

    double precision, allocatable, dimension(:) :: theta
    double precision, allocatable, dimension(:) :: phi

    double precision, allocatable, dimension(:) :: minimums 
    double precision, allocatable, dimension(:) :: maximums
    integer, allocatable, dimension(:) :: hypercube_indices
    integer, allocatable, dimension(:) :: physical_indices
    integer :: i



    interface
        function loglikelihood(theta,phi,context)
            double precision, intent(in),  dimension(:) :: theta
            double precision, intent(out),  dimension(:) :: phi
            integer,          intent(in)                 :: context
            double precision :: loglikelihood
        end function
    end interface





    ! ======= (1) Initialisation =======
    ! We need to initialise:
    ! a) mpi threads
    ! b) random number generator
    ! c) model
    ! d) program settings


    ! ------- (1a) Initialise MPI threads -------------------
#ifdef MPI
    call mpi_initialise()
#endif

    ! ------- (1b) Initialise random number generator -------
    ! Initialise the random number generator with the system time
    ! (Provide an argument to this if you want to set a specific seed
    ! leave argumentless if you want to use the system time)
    call initialise_random()


    ! ------- (1c) Initialise the model -------
    ! (i) Choose the loglikelihood
    !       Possible example likelihoods:
    !       - gaussian_loglikelihood
    !       - gaussian_shell
    !       - rosenbrock_loglikelihood
    !       - himmelblau_loglikelihood
    !       - rastrigin_loglikelihood
    !       - eggbox_loglikelihood
    !       - gaussian_loglikelihood_corr
    !       - gaussian_loglikelihood_cluster
    loglikelihood => gaussian_loglikelihood_corr

    ! (ii) Set the dimensionality
    settings%nDims=2                  ! Dimensionality of the space
    settings%nDerived = 0             ! Assign the number of derived parameters

    ! (iii) Assign the priors
    call allocate_indices(settings)

    ! (v) Set up priors
    allocate(minimums(settings%nDims))
    allocate(maximums(settings%nDims))
    allocate(physical_indices(settings%nDims))
    allocate(hypercube_indices(settings%nDims))

    minimums=0.5-1d-2*5
    maximums=0.5+1d-2*5

    do i=1,settings%nDims
        physical_indices(i)  = i
        hypercube_indices(i) = i
    end do

    call initialise_uniform(priors(1),hypercube_indices,physical_indices,minimums,maximums)




    ! ------- (1d) Initialise the program settings -------
    settings%nlive                = 500!25*settings%nDims        !number of live points
    settings%chain_length         = settings%nDims*10        !Number of chords to draw

    settings%nstack               =  settings%nlive*10       !number of points in the 'stack'
    settings%file_root            =  'chains/test'           !file root
    settings%sampler              => SliceSampling           !Sampler choice
    settings%get_nhat             => Adaptive_Parallel       !Direction choice
    settings%process_live_points  => get_live_coordinates    !no processing of live points needed

    settings%evidence_calculator  => KeetonEvidence          !evidence calculator
    settings%feedback             =  1                       !degree of feedback

    ! stopping criteria
    settings%precision_criterion  =  1d-1                    !degree of precision in answer
    settings%max_ndead            =  100000                  !maximum number of samples

    ! posterior calculation
    settings%nmax_posterior       = 100000                   !max number of posterior points
    settings%minimum_weight       = 1d-6                     !minimum weight of the posterior points
    settings%calculate_posterior  = .false.                  !calculate the posterior (slows things down at the end of the run)

    ! reading and writing
    settings%read_resume          = .false.                  !whether or not to resume from file
    settings%write_resume         = .false.                  !whether or not to write resume files
    settings%update_resume        = settings%nlive           !How often to update the resume files
    settings%write_live           = .true.                   !write out the physical live points?
    settings%save_all             = .false.                  !Save all the dead points?

    ! Evidence inference
    settings%infer_evidence       = .false.
    settings%evidence_samples     = 100000 


    ! Initialise the loglikelihood
    allocate(theta(settings%nDims),phi(settings%nDerived))
    loglike = loglikelihood(theta,phi,0)


    ! ======= (2) Perform Nested Sampling =======
    ! Call the nested sampling algorithm on our chosen likelihood and priors

#ifdef MPI
    if (mpi_size()>1) then
        output_info = NestedSamplingP(loglikelihood,priors,settings)
    else
        settings%nstack=settings%nlive
        output_info = NestedSamplingL(loglikelihood,priors,settings) 
    end if
#else
    settings%nstack=settings%nlive
    output_info = NestedSamplingL(loglikelihood,priors,settings) 
#endif 



    ! ======= (3) De-initialise =======
    ! De-initialise the random number generator 
    call deinitialise_random()

#ifdef MPI
    call mpi_finalise()
#endif


end program main
