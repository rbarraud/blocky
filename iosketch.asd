;;; -*- Mode: Lisp; -*-

;; ASDF Manual: http://constantly.at/lisp/asdf/

(defpackage :ioforms-asd)

(in-package :ioforms-asd)

(asdf:defsystem ioforms
  :name "ioforms"
  :version "0.2"
  :maintainer "David T O'Toole <dto1138@gmail.com>"
  :author "David T O'Toole <dto1138@gmail.com>"
  :license "General Public License (GPL) Version 3"
  :description "An object-oriented graphical 2D game engine."
  :serial t
  :depends-on (:lispbuilder-sdl 
	       :lispbuilder-sdl-image 
	       :lispbuilder-sdl-gfx
	       :lispbuilder-sdl-ttf
	       :lispbuilder-sdl-mixer)
  :components ((:file "ioforms")
	       (:file "prototypes")
	       (:file "math")
	       (:file "rgb")
	       (:file "keys")
	       (:file "console")
	       (:file "widgets")
	       (:file "viewport")
	       (:file "cells")
	       (:file "gcells")
	       (:file "gsprites")
	       (:file "narration")
	       (:file "browser")
	       (:file "mission")
	       (:file "forms")
	       (:file "blocks")
	       (:file "worlds")
;;	       (:file "path")
	       (:file "util")))
	       
	       
