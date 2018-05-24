#
#   Allows the PETSc dynamic library to be used from Julia. (http::/julialang.org)
#     PETSc must be configured with --with-shared-libraries

module PETSc2


using MPI
using ArrayViews
include("petsc_constants.jl")  # typedefs and constants
include("error.jl")  # error handling

import Base.show

# export all names
export PetscInitialize, PetscInitialized, getPETSC_COMM_SELF, PetscView, IS, PetscDestroy, ISSetType, ISGetSize, ISGetIndices, PetscDataTypeFromString, PetscDataTypeGetSize, PetscFinalize



# -------------------------------------
#=
function echodemo(filename)
  f = open(filename)
  h = readall(f)
  close(f)
  pos = 0
  while (pos <= length(h))
    (ex,pos)=parse(h,pos)
    str = string(ex.args)
    if _jl_have_color
      print("\033[1m\033[30m")
    end
    #  the next line doesn't work right for multiple line commands like for loops
    println(str[2:strlen(str)-1])
    if _jl_have_color
      print(_jl_answer_color())
      println(" ") # force a color change, otherwise answer color is not used
    end
    e = eval(ex)
    println(" ")
  end
end
=#
# -------------------------------------


#=
INSERT_VALUES = 1;
ADD_VALUES    = 2;
PETSC_COPY_VALUES   = 0;

PETSC_NORM_1         = 0;
PETSC_NORM_2         = 1;
PETSC_NORM_FROBENIUS = 2;
PETSC_NORM_INFINITY  = 3;
PETSC_NORM_MAX       = PETSC_NORM_INFINITY;
=#

# -------------------------------------
#    These are the Julia interface methods for all the visible PETSc functions. Julia datatypes for PETSc objects simply contain the C pointer to the
#    underlying PETSc object.
#
# -------------------------------------

"""
  PetscInitialized

  **Outputs**

   * Bool
"""
function PetscInitialized()
  init = Array(PetscBool, 1);
  err = ccall( (:PetscInitialized,  libpetsclocation),Int32,(Ptr{PetscBool},), init);

  return init[1] == PETSC_TRUE
end

"""
  PetscFinalize
"""
function PetscFinalize()
  gc() # call garbage collection to force all PETSc objects be destroy that are queued up for destruction
  return ccall( (:PetscFinalize,  libpetsclocation),Int32,());
end


 
"""
  PetscInitialize
"""
function PetscInitialize()
  PetscInitialize([])
end

"""
  PetscInitialize

  **Inputs**

   * args: Array{ASCIIString, 1} containing Petsc options keys and values
"""
function PetscInitialize(args)
  PetscInitialize(args,"","")
end

function PetscInitialize(args,filename,help)
  # argument list starts with program name
  args = ["julia";args];
#  println("typeof(args) = ", typeof(args))
  #
  #   If the user forgot to PetscFinalize() we do it for them, before restarting PETSc
  #

 init = PetscInitialized()
 if (init)
#    gc() # call garbage collection to force all PETSc objects be destroy that are queued up for destruction
#    err = ccall( (:PetscFinalize,  libpetsclocation),Int32,());if (err != 0) return err; end
    err = PetscFinalize()

    if err != 0
      return err
    end
  end

  # convert arguments to Cstring
  arr = Array(Ptr{UInt8}, length(args))
  for i = 1:length(args)
    arr[i] = pointer(Base.cconvert(Cstring, args[i]))
    # = cstring(args[i])
  end
#  ptrs = _jl_pre_exec(arr)
#  err = ccall(Libdl.dlsym(libpetsc, :PetscInitializeNoPointers),Int32,(Int32,Ptr{Ptr{UInt8}},Ptr{UInt8},Ptr{UInt8}), length(ptrs), ptrs,cstring(filename),cstring(help));

  err = ccall( (:PetscInitializeNoPointers,  libpetsclocation),Int32,(Int32,Ptr{Ptr{UInt8}},Cstring,Cstring), length(arr), arr,filename,help);
  return err
end

function getPETSC_COMM_SELF()
  comm = Array(MPI.CComm, 1)
  err = ccall( (:PetscGetPETSC_COMM_SELF,  libpetsclocation),Int32,(Ptr{comm_type},),comm);
  return convert(MPI.Comm, comm[1])
#   return MPI.COMM_WORLD.val
end

function PetscDataTypeFromString(name::AbstractString)
    ptype = Array(Cint, 1)
    found = Array(PetscBool, 1)
    ccall((:PetscDataTypeFromString,petsc),PetscErrorCode,(Cstring,Ptr{PetscDataType},Ptr{PetscBool}), name, ptype, found)

    return ptype[1], convert(Bool, found[1])
end


function PetscDataTypeGetSize(dtype::PetscDataType)
    datasize = Array(Csize_t, 1)
    ccall((:PetscDataTypeGetSize,petsc),PetscErrorCode,(PetscDataType,Ptr{Csize_t}), dtype, datasize)

    return datasize[1]
end






# -------------------------------------
#
#abstract PetscObject

function PetscView(obj)
  PetscView(obj,0)
end

type IS
  pobj::Ptr{Void}
  function IS(comm::MPI_Comm)
#    comm = PETSC_COMM_SELF();
    is = Array(Int64,1)
    err = ccall( (:ISCreate,  libpetsclocation),Int32,(comm_type,Ptr{Void}),comm,is)
#    if (err != 0)  # return type stability
#      return err
#    end
    is_ = new(is[1])
    finalizer(is_,PetscDestroy)
    # does not seem to be called immediately when is is no longer visible, is it called later during garbage collection?
    return is_
  end
end

  function PetscDestroy(is::IS)
    if (is.pobj != 0) then
      err = ccall( ( :ISDestroy,  libpetsclocation),PetscErrorCode,(Ptr{Void},), &is.pobj);
    end
    is.pobj = 0
    println("ISDestroy called")
    return 0
  end

  function IS(indices::Array{PetscInt})
    is = IS()
    err = ccall( ( :ISSetType,  libpetsclocation),PetscErrorCode,(Ptr{Void},Cstring), is.pobj,"general");
    err = ccall( (:ISGeneralSetIndices,  libpetsclocation), PetscErrorCode, (Ptr{Void}, PetscInt, Ptr{PetscInt},Int32),is.pobj,length(indices), indices, PETSC_COPY_VALUES)
    return is
  end

  function ISSetType(vec::IS, name)
    err = ccall( (:ISSetType,  libpetsclocation),PetscErrorCode,(Ptr{Void},Cstring), vec.pobj,name);
  end

  function PetscView(obj::IS,viewer)
  # what is the viewer argument used for?
   err = ccall( ( :ISView,  libpetsclocation),PetscErrorCode,(Ptr{Void},Int64),obj.pobj,0);
  end

  function ISGetSize(obj::IS)
    n = Array(PetscInt, 1)
    err = ccall( ( :ISGetSize,  libpetsclocation), PetscErrorCode,(Ptr{Void}, Ptr{PetscInt}), obj.pobj, n);
    return n[1]
  end

  # this should really take the indices array as an arguments
  function ISGetIndices(obj::IS)
    len = ISGetSize(obj)
    indices = Array(PetscInt,len)
    err = ccall( (:ISGetIndicesCopy,  libpetsclocation), PetscErrorCode,(Ptr{Void},Ptr{PetscInt}),obj.pobj,indices);

    return indices
  end

# -------------------------------------
#

include("vec.jl")

# -------------------------------------
include("mat.jl")

# -------------------------------------
include("ksp.jl")

# -------------------------------------
include("pc.jl")

# -------------------------------------
include("options.jl")

end  # end module


