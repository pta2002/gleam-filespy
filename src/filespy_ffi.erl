-module(filespy_ffi).
-export([identity/1]).

% Used in coercion.
identity(X) -> X.
