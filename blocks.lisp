;;; blocks.lisp --- A visual programming language inspired by MIT Scratch

;; Copyright (C) 2010  David O'Toole

;; Author: David O'Toole <dto@gnu.org>
;; Keywords: oop, languages, mouse, lisp, multimedia, hypermedia

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; This file implements a drag-and-drop visual programming language in
;; the style of Smalltalk environments such as Squeak Morphic and MIT
;; Scratch.

;;; Code:

(in-package :iosketch)

;; For the design I've followed a motto associated with the visual
;; programming language Pure Data: "The diagram is the program."
;; Since the diagram is 2D, the program must therefore be
;; two-dimensional as well. That means every block in the program
;; (i.e. every expression) must have an X,Y position.

;; Besides a 2D position, each block has a (possibly empty) list of
;; arguments. Arguments are symbols like :move or :play-sound, or data
;; arguments such as numbers, strings, or symbols. Arguments may also be
;; objects and this involves nested blocks in the diagram.

(define-prototype block ()
  (x :documentation "Integer X coordinate of this block's position.")
  (y :documentation "Integer Y coordinate of this block's position.")
  (width :documentation "Cached pixel width of block.")
  (height :documentation "Cached pixel height of block.")
  (arguments :documentation "List of block argument values.")
  (schema :documentation "List of CL type specifiers for corresponding expressions in <arguments>.")
  (operation :initform "block" :documentation "Symbol name of block's operation, i.e. message key.")
  (type :documentation "Type name of block. See also `*block-types*'."))

(defmacro defblock (name &body args)
  `(define-prototype ,name (:parent =block=)
     (operation :initform ,(make-keyword name))
     ,@args))

(defparameter *argument-types*
  '(:block :sprite :integer :float :number 
    :string :symbol :unit :direction :body))

(defparameter *block-types*
  '(:system :motion :event :message :looks :sound 
    :control :comment :sensing :operators :variables))

(defparameter *background-color* ".white")

(defparameter *block-font* "sans-condensed-bold-12")

(defvar *dash-size* 3)

(defparameter *block-colors* 
  '(:motion ".cornflower blue"
    :system ".gray50"
    :event ".gray80"
    :comment ".grey70"
    :looks ".purple"
    :sound ".orchid"
    :message ".sienna3"
    :control ".orange1"
    :variables ".DarkOrange2"
    :operators ".green1"
    :sensing ".DeepSkyBlue3")
  "X11 color names of the different block types.")

(defparameter *block-highlight-colors*
  '(:motion ".sky blue"
    :system ".gray80"
    :event ".gray90"
    :comment ".grey90"
    :looks ".medium orchid"
    :sound ".plum"
    :message ".sienna2"
    :control ".gold"
    :variables ".DarkOrange1"
    :operators ".chartreuse3"
    :sensing ".DeepSkyBlue2")
  "X11 color names of highlights on the different block types.")

(defparameter *block-shadow-colors* 
  '(:motion ".slate blue"
    :system ".gray50"
    :event ".gray70"
    :comment ".grey40"
    :looks ".dark orchid"
    :sound ".violet red"
    :message ".chocolate3"
    :control ".dark orange"
    :variables ".OrangeRed2"
    :operators ".green3"
    :sensing ".turquoise3")
  "X11 color names of shadows on the different block types.")

(defparameter *block-foreground-colors* 
  '(:motion ".white"
    :system ".white"
    :event ".gray40"
    :comment ".gray30"
    :message ".white"
    :looks ".white"
    :sound ".white"
    :control ".white"
    :variables ".white"
    :operators ".white"
    :sensing ".white")
  "X11 color names of the text used for different block types.")

(defun block-color (type &optional (part :background))
  (let ((colors (ecase part
		  (:background *block-colors*)
		  (:highlight *block-highlight-colors*)
		  (:shadow *block-shadow-colors*)
		  (:foreground *block-foreground-colors*))))
    (getf colors type)))

(defparameter *small-block-corners* '(:top-left ".top-left-corner-small"
				      :top-right ".top-right-corner-small"
				      :bottom-right ".bottom-right-corner-small"
				      :bottom-left ".bottom-left-corner-small"))

(defparameter *medium-block-corners* '(:top-left ".top-left-corner-medium"
				       :top-right ".top-right-corner-medium"
				       :bottom-right ".bottom-right-corner-medium"
				       :bottom-left ".bottom-left-corner-medium"))

(defparameter *default-block-corner-size* :small)

(defun block-corner (corner &optional (size *default-block-corner-size*))
  (let ((images (ecase size
		  (:medium *medium-block-corners*)
		  (:small *small-block-corners*))))
    (getf images corner)))

(defun block-corner-size (&optional (size *default-block-corner-size*))
  (ecase size
    (:small 5)
    (:medium 9)))

(define-method count block () 1)

(define-method move block (x y)
  (setf <x> x)
  (setf <y> y))

(define-method hit block (click-x click-y)
  (with-fields (x y width height) self
    (when (within-extents click-x click-y 
			  x y 
			  (+ x width)
			  (+ y height))
      self)))

(define-method arrange block ()
  (let ((font *block-font*)
	(line (string-downcase (format nil "~{~a~^ ~}" (cons <operation> <arguments>)))))
    (setf <width> (+ (* 6 *dash-size*) ;; spacing
		     (font-text-extents line font)))
    (setf <height> (+ (* 2 *dash-size*)
		      (font-height font)))))

(define-method get-argument block (index)
  (nth index <arguments>))

(define-method set-argument block (index value)
    (setf (nth index <arguments>) value)
    (/arrange self))

(define-method execute block (recipient)
  "Send the appropriate message to the RECIPIENT object."
  (apply #'iosketch:send nil <operation> recipient <arguments>))

(define-method describe block ()
  "Show name and comprehensive help for this block.")

(define-method draw block (image)
  (with-field-values (x y type height width schema) self
    (let* ((foreground (block-color type :foreground))
	   (background (block-color type :background))
	   (highlight (block-color type :highlight))
	   (shadow (block-color type :shadow))
	   (space *dash-size*)
	   (label (string-downcase (format nil "~{~a~^ ~}" (cons <operation> <arguments>))))
	   (corner (block-corner-size))
	   (bottom (+ y height))
	   (right (+ x width)))
      (draw-box x y width height
		:color background
		:stroke-color background
		:destination image)
      (draw-string-blended label 
			   (+ x (* 3 space))
			   (+ y space)
			   :foreground foreground
			   :destination image
			   :font *block-font*)
      ;; top left
      (draw-resource-image (block-corner :top-left)
			   x y :destination image)
      (draw-line (+ x corner) y
		 x (+ y corner)
		 :color highlight
		 :destination image)
      ;; top
      (draw-line (+ x corner) y
		 (- right corner) y
		 :color highlight
		 :destination image)
      ;; top right
      (draw-resource-image (block-corner :top-right)
			   (- right corner) y 
			   :destination image)
      (draw-line (- right corner) y
		 right (+ y corner)
		 :color background
		 :destination image)
      ;; right
      (draw-line right (+ y corner)
		 right (- bottom corner)
		 :color shadow
		 :destination image)
      ;; bottom right
      (draw-resource-image (block-corner :bottom-right)
			   (- right corner)
			   (- bottom corner)
			   :destination image)
      (draw-line (- right corner) bottom
		 right (- bottom corner)
		 :color shadow
		 :destination image)
      (draw-line (- right corner 1) bottom
		 (- right 1) (- bottom corner)
		 :color background
		 :destination image)
      ;; bottom 
      (draw-line (+ x corner) bottom
		 (- right corner 1) bottom
		 :color shadow
		 :destination image)
      ;; bottom left
      (draw-resource-image (block-corner :bottom-left)
			   x (- bottom corner)
			   :destination image)
      (draw-line x (- bottom corner)
		 (+ x corner) bottom
		 :color background 
		 :destination image)
      ;; left 
      (draw-line x (+ y corner) 
		 x (- bottom corner)
		 :color highlight
		 :destination image))))

;;; Predefined blocks for sending various common messages 

(defblock move
  (type :initform :motion)
  (schema :initform '(:direction :integer :unit))
  (arguments :initform '(:north 10 :pixels)))

(defblock move-to
  (type :initform :motion)
  (schema :initform '(:unit :integer :integer))
  (arguments :initform '(:space 0 0)))

(defblock music 
  (type :initform :sound)
  (schema :initform '(:string :keyword :keyword))
  (arguments :initform '("fanfare" :loop :no)))

(defblock when 
  (type :initform :control)
  (schema :initform '(:predicate :block))
  (arguments :initform '(nil nil)))

(defblock if 
  (type :initform :control)
  (schema :initform '(:predicate :block :block))
  (arguments :initform '(nil nil nil)))

(defblock do
  (type :initform :event)
  (schema :initform '(:symbol :body))
  (body :initform nil)
  (arguments :initform nil))

(defun is-event-block (thing)
  (and (not (null thing))
       (iosketch:object-p thing)
       (has-field :operation thing)
       (eq :do (field-value :operation thing))))

;;; Composing blocks into larger programs

(define-prototype script ()
  (blocks :initform ()
	  :documentation "List of blocks in the script.")
  (variables :initform (make-hash-table :test 'eq)))

(define-method initialize script (&key blocks variables)
  (when blocks (setf <blocks> blocks))
  (when variables (setf <variables> variables)))

(defvar *script*)

(define-method add script (block x y)
  (with-fields (blocks) self
    (setf blocks (adjoin block blocks))
    (/move block x y)))

(define-method delete script (block)
  (with-fields (blocks) self
    (setf blocks (delete block blocks))))

(define-method set script (var value)
  (setf (gethash var <variables>) value))

(define-method get script (var)
  (gethash var <variables>))

(defun script-variable (var-name)
  (/get *script* var-name))

(defun set-script-variable (var-name value)
  (/set *script* var-name value))

(defsetf script-variable set-script-variable)

(defmacro with-script-variables (vars &rest body)
  (labels ((make-clause (sym)
	     `(,sym (script-variable ,(make-keyword sym)))))
    (let* ((symbols (mapcar #'make-non-keyword vars))
	   (clauses (mapcar #'make-clause symbols)))
      `(symbol-macrolet ,clauses ,@body))))

;;; Script editor widget

(defwidget editor
  (script :initform nil 
	  :documentation "The IOSKETCH:=SCRIPT= object being edited.")
  (selection :initform ()
  	     :documentation "Subset of selected blocks.")
  (focus :initform nil
  	 :documentation "Block with current focus.")
  (drag :initform nil 
  	:documentation "Block being dragged, if any.")
  (drag-start :initform nil
	      :documentation "A cons (X . Y) of widget where last started.")
  (drag-offset :initform nil
	       :documentation "A cons (X . Y) of mouse click location on block.")
  (modified :initform nil 
  	    :documentation "Non-nil when modified since last save."))

(define-method render editor ()
  (with-fields (script image selection focus drag modified) self   
    (when script
      (with-fields (blocks) script
	(/clear self *background-color*)
	(unless drag 
	  (dolist (block blocks)
	    (/arrange block)))
	(dolist (block blocks)
	  (/draw block image))))))

(define-method mouse-down editor (x y &optional button)
  (with-fields (script selection focus drag modified) self
    (when script 
      (with-fields (blocks) script
	(labels ((hit (b)
		   (/hit b x y)))
	  (let ((block (some #'hit blocks)))
	    (setf drag block)
	    (setf focus block)))))))

(define-method mouse-move editor (mouse-x mouse-y)
  (with-fields (script selection focus drag-start drag modified) self
    (when drag
      (with-fields (x y) drag
	(when (null drag-start)
	  (setf drag-start (cons x y))
	  (setf drag-offset (cons (- mouse-x x)
				  (- mouse-y y))))
	(destructuring-bind (x0 . y0) drag-offset
	  (/move drag (- mouse-x x0) (- mouse-y y0)))))))

(define-method mouse-up editor (x y &optional button)
  (with-fields (script drag-start selection focus drag modified) self
    (setf drag-start nil)
    (setf drag-offset nil)
    (setf drag nil)))


;; (define-method drag editor (x y))

;; (define-method drop editor (x y))
      
;;; blocks.lisp ends here
