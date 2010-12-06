(require 'sb-posix)

(push (merge-pathnames "lib/" (values *default-pathname-defaults*))
      asdf:*central-registry*)

(asdf:oos 'asdf:load-op 'iosketch)

(cffi:close-foreign-library 'sdl-gfx-cffi::sdl-gfx)
(cffi:close-foreign-library 'sdl-mixer-cffi::sdl-mixer)
(cffi:close-foreign-library 'sdl-image-cffi::sdl-image)
(cffi:close-foreign-library 'sdl-cffi::sdl)

(sb-ext:save-lisp-and-die "sanctuary"
			  :toplevel (lambda ()
				      (sb-posix:putenv
				       (format nil "SBCL_HOME=~A" 
					       #.(sb-ext:posix-getenv "SBCL_HOME")))
				      (let ((iosketch:*executable* t))
					(iosketch:play "forest"))
				      0)
			  :executable t)
  
  
