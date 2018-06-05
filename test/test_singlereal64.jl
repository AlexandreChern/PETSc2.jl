using Base.Test
using PETSc2
@testset "  ---Checking Petsc data types---" begin

  @test ( PetscScalar )== Float32
  @test ( PetscReal )== Float32
  @test ( PetscInt )== Int64

end


