;;; blocks.lisp --- core visual language model for Blocky

;; Copyright (C) 2010, 2011 David O'Toole

;; Author: David O'Toole <dto@ioforms.org>
;; Keywords: oop, languages, mouse, lisp, multimedia, hypermedia

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hopes that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>

;;; Commentary:

;; Please see the included files README.org and guide.org for an
;; overview.

;;; Code:

(in-package :blocky)

(define-prototype block 
    (:documentation
     "Blocks are the visual programming elements that programs in the
Blocky language are built up from. The prototypal block defined here
establishes the default properties and behaviors of blocks, and the
default means of composing individual blocks into larger programs.

For an overview of the Blocky programming model, see the preamble to
the Blocky Reference Guide in the included file `guide.org', or on the
Web at:

 http://blocky.io/reference.html 
")
  (cursor-clock :initform 0)
  ;; general information
  (inputs :initform nil)
  (input-names :initform nil)
  (results :initform nil)
  (category :initform :data)
  (tags :initform nil)
  (garbagep :initform nil)
  (temporary :initform nil)
  (methods :initform '(:make-reference :move-toward :add-tag :remove-tag :duplicate :make-sibling :move :move-to :play-sound :show :hide :is-visible))
  (parent :initform nil :documentation "Link to enclosing parent block, or nil if none.")
  (events :initform nil :documentation "Event bindings, if any. See also `bind-event'.")
  (default-events :initform nil)
  (operation :initform :block)
  ;; visual layout
  (x :initform 0 :documentation "X coordinate of this block's position.")
  (y :initform 0 :documentation "Y coordinate of this block's position.")
  (z :initform 0 :documentation "Z coordinate of this block's position.")
  (heading :initform 0.0 :documentation "Heading angle of this block, in radians. See also `radian-angle'.")
  (quadtree-node :initform nil)
  (excluded-fields :initform '(:quadtree-node))
  ;; 
  (last-x :initform nil)
  (last-y :initform nil)
  (last-z :initform nil)
  ;; blending
  (blend :initform :alpha)
  (opacity :initform 1.0)
  ;; collisions
  (collision-type :initform :default)
  ;; dimensions
  (width :initform 32 :documentation "Width of the block, in GL units.")
  (height :initform 32 :documentation "Height of the block, in GL units.")
  (depth :initform 32 :documentation "Depth of block, in GL units. Currently ignored.")
  (pinned :initform nil) ;; when non-nil, do not allow dragging
  (visible :initform t)
  ;; morphic style halo
  (halo :initform nil)
  (mode :initform nil)
  (name :initform nil)
  (needs-layout :initform t)
  (label :initform nil)
  (tasks :initform nil)
  (image :initform nil :documentation "Name of texture to be displayed, if any."))

;;; Defining blocks

(defmacro define-block (spec &body args)
  "Define a new block.
The first argument SPEC is either a
symbol naming the new block, or a list of the form
 (SYMBOL . PROPERTIES) Where SYMBOL is similarly a name symbol but
PROPERTIES is a keyword property list whose valid keys
are :SUPER (specifying which prototype the newly defined block will
inherit behavior from) and :DOCUMENTATION (a documentation string.)
The remaining arguments ARGS are field specifiers, each of which is
either a symbol naming the field, or a list of the form (SYMBOL
. PROPERTIES) with :INITFORM and :DOCUMENTATION as valid keys."
  (let ((name0 nil)
	(super0 "BLOCKY:BLOCK"))
    (etypecase spec
      (symbol (setf name0 spec))
      (list (destructuring-bind (name &key super) spec
	      (setf name0 name)
	      (when super (setf super0 super)))))
    `(define-prototype ,name0 (:super ,(make-prototype-id super0))
       (operation :initform ,(make-keyword name0))
       ,@(if (keywordp (first args))
	  (plist-to-descriptors args)
	  args))))

(defparameter *block-categories*
  '(:system :motion :event :message :looks :sound :structure :data :button
    :menu :hover :control :comment :sensing :operators :variables)
  "List of keywords used to group blocks into different functionality
areas.")

;;; Adding blocks to the simulation

(define-method start block ()
  "Add this block to the simulation so that it receives update events."
  (unless (find self *blocks* :test 'eq :key #'find-object)
    (setf *blocks* (adjoin self *blocks*))))

(define-method stop block ()
  "Remove this block from the simulation so that stops getting update
events."
  (setf *blocks* (delete self *blocks* :test #'eq :key #'find-object)))

;;; Defining composite blocks more simply

;(declaim (inline input-block))

(defun input-block (object input-name)
  (nth (position input-name 
		 (%input-names object))
       (%inputs object)))

(defmacro define-block-macro (name 
     (&key (super "BLOCKY:BLOCK") fields documentation inputs)
     &body body)
  "Define a new block called NAME according to the given options.

The argument SUPER should be the name (a symbol or string) of the base
prototype to inherit traits (data and behavior) from. The default is
`block' so that if you don't specify a SUPER argument, you still
inherit all the inbuilt behaviors of blocks.

The argument FIELDS should be a list of field descriptors, the same as
would be given to `define-prototype'.

The INPUTS argument is a list of forms evaluated to produce argument
blocks. 

DOCUMENTATION is an optional documentation string for the entire
macro.

The BODY forms are evaluated when the resulting block is evaluated;
they operate by invoking `evaluate' in various ways on the INPUTS.

The method `recompile' emits Lisp code that has the same result as
invoking `evaluate', but with zero or more blocks in the entire visual
expression subtree being replaced by (possibly shorter and more
efficient) 'plain' Lisp code. This is trivially true for the default
implementation of `recompile', which emits a statement that just
invokes `evaluate' when evaluated. When subsequently redefining the
`recompile' method on a block-macro, the 'equivalence' between the
results of invoking `recompile' and invoking `evaluate' depends solely
on the implementor, who can write a `recompile' method which operates
by invoking `recompile' in various ways on the macro-block's
`%inputs', and emitting Lisp code forms using those compiled code
streams as a basis. 
"
  (let ((input-names (remove-if-not #'keywordp inputs)))
    `(progn 
       ;; define input accessor functions
       ,@(mapcar #'make-input-accessor-defun-forms input-names)
       (define-block (,name :super ,super) 
	 (label :initform ,(pretty-symbol-string name))
	 (input-names :initform ',input-names)
	 ,@fields)
       (define-method initialize ,name ()
	 (apply #'initialize%super self %inputs) 
	 (setf %inputs (list ,@(remove-if #'keywordp inputs)))
	 (update-parent-links self)
	 ,@body)
       (define-method recompile ,name () `(evaluate self)))))

;;; Block lifecycle

(define-method initialize block (&rest blocks)
  "Prepare an empty block, or if BLOCKS is non-empty, a block
initialized with BLOCKS as inputs."
  (setf %inputs 
	(or blocks (default-inputs self)))
  (update-parent-links self)
  (update-result-lists self)
  (bind-any-default-events self)
  (register-uuid self)
  ;; textures loaded here may be bogus; do this later
  (when %image
    (resize-to-image self))
  (setf %x 0 %y 0))

(define-method destroy block ()
  "Throw away this block."
  (mapc #'destroy %inputs)
  (when %halo (destroy %halo))
  (when %parent 
    (unplug-from-parent self))
  (remove-thing-maybe (world) self)
  (setf %garbagep t))

(define-method dismiss block ()
  (if (windowp %parent)
      (dismiss %parent)
      (destroy self)))

(define-method exit block ()
  (destroy-block *world* self))

(define-method make-duplicate block ()
  (duplicate self))

(define-method make-clone block ()
  (find-uuid (clone (find-super self))))

(define-method register-uuid block ()
  (add-object-to-database self))

;;; Block tags, used for categorizing blocks

(define-method has-tag block 
    ((tag symbol :default nil :label ""))
  "Return non-nil if this block has the specified TAG.

Blocks may be marked with tags that influence their processing by the
engine. The field `%tags' is a set of keyword symbols; if a symbol
`:foo' is in the list, then the block is in the tag category `:foo'.
"
  (member tag %tags))

(define-method add-tag block 
    ((tag symbol :default nil :label ""))
  "Add the specified TAG symbol to this block."
  (pushnew tag %tags))

(define-method remove-tag block 
    ((tag symbol :default nil :label ""))
  "Remove the specified TAG symbol from this block."
  (setf %tags (remove tag %tags)))

;;; Serialization hooks

(define-method before-serialize block ())

(define-method after-deserialize block ()
  "Prepare a deserialized block for running."
  (register-uuid self))

;;; Expression structure (blocks composed into trees)

(define-method adopt block (child)
  (when (get-parent child)
    (unplug-from-parent child))
  (set-parent child self))

(define-method set-value block (value))

(define-method update-parent-links block ()
  (dolist (each %inputs)
    (set-parent each self)))

(define-method can-accept block () nil)

(define-method accept block (other-block)
  "Try to accept OTHER-BLOCK as a drag-and-dropped input. Return
non-nil to indicate that the block was accepted, nil otherwise."
  nil)

(defvar *buffer* nil
  "When non-nil, the UUID of the current buffer object.")

(define-method contains block (block)
  (find (find-object block)
	%inputs
	:test 'eq
	:key #'find-object))

(define-method input-position block (input)
  (assert (not (null input)))
  (position (find-uuid input) %inputs :key #'find-uuid :test 'equal))

(defun input (self name)
  (with-fields (inputs) self
    (assert (not (null inputs)))
    (nth (input-position self name) inputs)))

(defun (setf input) (self name block)
  (with-fields (inputs) self
    (assert (not (null inputs)))
    (set-parent block self)
    (setf (nth (input-position self name) inputs)
	  ;; store the real link
  	  (find-object block))))

(define-method position-within-parent block ()
  (input-position %parent self))

(define-method set-parent block (parent)
  "Store a UUID link to the enclosing block PARENT."
  (assert (not (null parent)))
  (assert (valid-connection-p parent self))
  (setf %parent (when parent 
		  ;; always store uuid to prevent circularity
		  (find-uuid parent))))
	       
(define-method get-parent block ()
  %parent)

(define-method find-parent block ()
  (find-uuid %parent))

(defun valid-connection-p (sink source)
  (assert (or sink source))
  ;; make sure source is not actually sink's parent somewhere
  (block checking
    (prog1 t
      (let ((pointer sink))
	(loop while pointer do
	  (if (eq (find-object pointer)
		  (find-object source))
	      (return-from checking nil)
	      (setf pointer (find-parent pointer))))))))

(define-method update-result-lists block ()
  (let ((len (length %inputs)))
    (setf %input-widths (make-list len :initial-element 0))
    (setf %results (make-list len))))

(define-method delete-input block (block)
  (with-fields (inputs) self
    (prog1 t
      (assert (contains self block))
      (setf inputs (remove block inputs
			   :key #'find-object
			   :test 'eq))
      (assert (not (contains self block))))))

(define-method default-inputs block ()
  nil)

(define-method this-position block ()
  (with-fields (parent) self
    (when parent
      (input-position parent self))))

(define-method plug block (thing n)
  "Connect the block THING as the value of the Nth input."
  (set-parent thing self)
  (setf (input self n) thing))

(define-method after-unplug-hook block (input))

(define-method unplug block (input)
  "Disconnect the block INPUT from this block."
  (with-fields (inputs parent) self
    (assert (contains self input))
    (prog1 input
      (setf inputs 
	    (delete input inputs 
		    :test 'eq :key #'find-object))
      (after-unplug-hook self input))))

(define-method unplug-from-parent block ()
  (prog1 t
    (with-fields (parent) self
      (assert (not (null parent)))
      (assert (contains parent self))
      (unplug parent self)
      (assert (not (contains parent self)))
      (setf parent nil))))

(define-method drop block (new-block &optional (dx 0) (dy 0))
  "Add a new object to the current world at the current position.
Optionally provide an x-offset DX and a y-offset DY.
See also `drop-at'."
  (add-object (world) new-block (+ %x dx) (+ %y dy)))

(define-method drop-at block (new-block x y)
  "Add the NEW-BLOCK to the current world at the location X,Y."
  (assert (and (numberp x) (numberp y)))
  (add-object (world) new-block x y))

;;; Defining input events for blocks

;; see also definition of "task" blocks below.

(define-method initialize-events-table-maybe block (&optional force)
  (when (or force 
	    (not (has-local-value :events self)))
    (setf %events (make-hash-table :test 'equal))))

(define-method bind-event-to-task block (event-name modifiers task)
  "Bind the described event to invoke the action of the TASK.
EVENT-NAME is either a keyword symbol identifying the keyboard key, or
a string giving the Unicode character to be bound. MODIFIERS is a list
of keywords like :control, :alt, and so on."
  (assert (find-object task))
  (initialize-events-table-maybe self)
  (let ((event (make-event event-name modifiers)))
    (setf (gethash event %events)
	  task)))

(define-method unbind-event block (event-name modifiers)
  "Remove the described event binding."
  (remhash (normalize-event (cons event-name modifiers))
	   %events))

(define-method handle-event block (event)
  "Look up and invoke the block task (if any) bound to
EVENT. Return the task if a binding was found, nil otherwise. The
second value returned is the return value of the evaluated task (if
any)."
  (with-fields (events) self
    (when events
      (let ((task 
	      ;; unpack event
	      (destructuring-bind (head &rest modifiers) event
		;; if head is a cons, check for symbol binding first,
		;; then for unicode binding. we do this because we'll
		;; often want to bind keys like ENTER or BACKSPACE
		;; regardless of their Unicode interpretation 
		(if (consp head)
		    (or (gethash (cons (car head) ;; try symbol
				       modifiers)
				 events)
			(gethash (cons (cdr head) ;; try unicode
				       modifiers)
				 events))
		    ;; it's not a cons. 
		    ;; just search event as-is
		    (gethash event events)))))
	(if task
	    (prog1 (values task (evaluate task))
	      (invalidate-layout self))
	    (values nil nil))))))

(define-method handle-text-event block (event)
  "Look up events as with `handle-event', but insert unhandled keypresses
as Unicode characters via the `insert' function."
  (unless (joystick-event-p event)
    (with-fields (events) self
      (destructuring-bind (key . unicode) (first event)
	(when (or (block%handle-event self (cons key (rest event)))
		  ;; treat Unicode characters as self-inserting
		  (when unicode
		    (send :insert self unicode)))
	  (invalidate-layout self))))))
  
(defun bind-event-to-method (block event-name modifiers method-name)
  "Arrange for METHOD-NAME to be sent as a message to this object
whenever the event (EVENT-NAME . MODIFIERS) is received."
  (destructuring-bind (key . mods) 
      (make-event event-name modifiers)
    (bind-event-to-task block 
			   key
			   mods
			   (new 'task method-name block))))

(define-method bind-event block (event binding)
  "Bind the EVENT to invoke the action specified in BINDING.
EVENT is a list of the form:

       (NAME modifiers...)

NAME is either a keyword symbol identifying the keyboard key, or a
string giving the Unicode character to be bound. MODIFIERS is a list
of keywords like :control, :alt, and so on.

Examples:
  
  (bind-event self '(:up) :move-up)
  (bind-event self '(:down) :move-down)
  (bind-event self '(:q :control) :quit)
  (bind-event self '(:escape :shift) :menu)

See `keys.lisp' for the full table of key and modifier symbols.

"  (destructuring-bind (name &rest modifiers) event
    (etypecase binding
      (symbol (bind-event-to-method self name modifiers binding))
      (list 
       ;; create a method call 
       (let ((task (new 'task
			   (make-keyword (first binding))
			   self
			   :arguments (rest binding))))
	 (bind-event-to-task self name modifiers task))))))

(define-method bind-any-default-events block ()
  (with-fields (default-events) self
    (when default-events
      (initialize-events-table-maybe self)
      (dolist (entry default-events)
	(apply #'bind-event self entry)))))

(defun bind-event-to-text-insertion (self key mods text)
  (bind-event-to-task self key mods 
			 (new 'task :insert self (list text))))
    
(define-method insert block (string)
  (declare (ignore string))
  nil)

(defvar *lowercase-alpha-characters* "abcdefghijklmnopqrstuvwxyz")
(defvar *uppercase-alpha-characters* "ABCDEFGHIJKLMNOPQRSTUVWXYZ")
(defvar *numeric-characters* "0123456789")
(defvar *graphic-characters* "`~!@#$%^&*()_-+={[}]|\:;\"'<,>.?/")

(defparameter *text-qwerty-keybindings*
  '(("a" (:control) :beginning-of-line)
    ("e" (:control) :end-of-line)
    ("f" (:control) :forward-char)
    ("b" (:control) :backward-char)
    (:home nil :beginning-of-line)
    (:end nil :end-of-line)
    (:right nil :forward-char)
    (:left nil :backward-char)
    ("k" (:control) :clear-line)
    (:backspace nil :backward-delete-char)
    (:delete nil :delete-char)
    ("d" (:control) :delete-char)
    (:return nil :enter)
    ("x" (:control) :exit)
    ("g" (:control) :exit)
    (:escape nil :exit)
    ("p" (:alt) :backward-history)
    ("n" (:alt) :forward-history)  
    (:up nil :backward-history)
    (:down nil :forward-history)))

(defparameter *arrow-key-text-navigation-keybindings*
  '((:up nil :previous-line)
    (:down nil :next-line)
    (:left nil :backward-char)
    (:right nil :forward-char))) 

(defun keybinding-event (binding)
  (cons (first binding)
	(second binding)))

(defun keybinding-action (binding)
  (nthcdr 2 binding))

(define-method install-keybindings block (keybindings)
  (dolist (binding keybindings)
    (bind-event self 
		(keybinding-event binding)
		(keybinding-action binding))))
        
(define-method install-text-keybindings block ()
  ;; install UI keys that will vary by locale
  (with-fields (events) self
    (setf events (make-hash-table :test 'equal))
    (dolist (binding *text-qwerty-keybindings*)
      (destructuring-bind (key mods result) binding
	(etypecase result
	  (keyword (bind-event-to-method self key mods result))
	  (string (bind-event-to-text-insertion self key mods result)))))))

;;; Pointer events (see also worlds.lisp)

(define-method select block () nil)

(define-method tap block (x y)
  (declare (ignore x y))
  nil)

(define-method alternate-tap block (x y)
  (toggle-halo self))

(define-method handle-point-motion block (x y)
  (declare (ignore x y)))

(define-method press block (x y button)
  (declare (ignore x y button)))

(define-method release block (x y button)
  (declare (ignore x y button)))

(define-method can-pick block () 
  (not %pinned))

(define-method pick block ()
  (if %pinned %parent self)) ;; Possibly return a child, or a new object 

(define-method after-place-hook block () nil)

;;; Focus events (see also shell.lisp)

(define-method focus block () nil)

(define-method lose-focus block () nil)

(define-method grab-focus block () 
  (send :focus-on (world) self))

;;; Squeak-style pop-up halo with action handles

;; see also halo.lisp

(define-method make-halo block ()
  (when (null %halo)
    (setf %halo (new 'halo self))
    (add-block (world) %halo)))

(define-method destroy-halo block ()
  (when %halo 
    (destroy %halo)
    (setf %halo nil)))

(define-method toggle-halo block ()
  (if %halo
      (destroy-halo self)
      (make-halo self)))

(define-method align-to-pixels block ()
  (setf %x (truncate %x))
  (setf %y (truncate %y)))

(define-method drag block (x y)
  (move-to self x y))

(define-method pick-drag block (x y)
  (declare (ignore x y)) 
  self)

(define-method can-escape block ()
  t)

;;; Tasks and updating

;; See also definition of "task" blocks below.

(define-method add-task block (task)
  (assert (blockyp task))
  (pushnew (find-uuid task) %tasks :test 'equal))

(define-method remove-task block (task)
  (assert (blockyp task))
  (setf %tasks (delete task %tasks :test 'equal)))

(define-method run block ()) ;; stub for with-turtle

(define-method run-tasks block ()
  ;; don't run tasks on objects that got deleted during UPDATE
  (when %quadtree-node
    ;; run tasks while they return non-nil 
    (setf %tasks (delete-if-not #'running %tasks))))

(define-method update block ()
  "Update the simulation one step forward in time."
  (mapc #'update %inputs))
   
;;; Creating blocks from S-expressions
 
(defun action-spec-p (spec)
  (and (listp spec)
       (symbolp (first spec))))

(defun list-spec-p (spec)
    (and (not (null spec))
	 (listp spec)))

(defun null-block-spec-p (spec)
  (and (not (null spec))
       (listp spec)
       (= 1 (length spec))
       (null (first spec))))

;; see also the definition of "entry" blocks in listener.lisp

(defparameter *builtin-entry-types* 
  '(integer float string symbol number))
 
(defun data-block (datum)
  (let* ((data-type (type-of datum))
	 (head-type (if (listp data-type)
			(first data-type)
			data-type))
	 (type-specifier 
	   (if (member head-type *builtin-entry-types* :test 'equal)
			     head-type data-type)))
    ;; see also listener.lisp for more on data entry blocks
    (typecase datum
      ;; see also the definition of "string" blocks in listener.lisp
      (string (new 'string :value datum))
      (symbol (new 'symbol :value datum))
      (otherwise (new 'entry :value datum :type-specifier type-specifier)))))
		    
(defvar *make-block-package* nil)

(defun make-block-package ()
  (or (project-package-name) (find-package :blocky)))

(defun make-block (sexp)
    "Expand VALUE specifying a block diagram into real blocks.
SEXP is of the form:

  (BLOCK-NAME ARG1 ARG2 ... ARGN)

Where BLOCK-NAME is the name of a prototype defined with `define-block'
and ARG1-ARGN are numbers, symbols, strings, or nested SEXPS."
  ;; use labels because we need to call make-block from inside
  (labels ((action-block (spec)
	     (destructuring-bind (proto &rest arguments) spec
	       (let ((prototype 		       
		      (find-prototype 
		       (make-prototype-id proto 
					  ;; wait, is this wrong? wrong prototype?
					  (or (make-block-package)
					      (find-package "BLOCKY")))))
		     (arg-blocks (mapcar #'make-block arguments)))
		 (message "arg-blocks ~S" (list (length arg-blocks)
		 				(mapcar #'find-uuid arg-blocks)))
		 (apply #'clone prototype arg-blocks))))
	   (list-block (items)
	     (apply #'clone "BLOCKY:LIST" (mapcar #'make-block items))))
    (let ((result 
	    (cond ((null-block-spec-p sexp)
		   (null-block))
		  ((blockyp sexp) ;; catch UUIDs etc
		   sexp)
		  ((stringp sexp)
		   (new 'string :value sexp))
		  ((action-spec-p sexp)
		   (action-block sexp))
		  ((list-spec-p sexp)
		   (list-block sexp))
		  ((not (null sexp)) (data-block sexp)))))
      (prog1 result
	(when result
	  (add-object-to-database (find-object result)))))))

;;; Block movement

(define-method save-location block ()
  (setf %last-x %x
	%last-y %y
	%last-z %z))

(define-method clear-saved-location block ()
  (setf %last-x nil
	%last-y nil
	%last-z nil))

(define-method restore-location block ()
  ;; is there a location to restore? 
  (when %last-x
    (when *quadtree* (quadtree-delete *quadtree* self))
    (setf %x %last-x
	  %y %last-y
	  %z %last-z)
    (when *quadtree* (quadtree-insert *quadtree* self))))

(define-method set-location block (x y)
  (setf %x x %y y))

(define-method move-to block 
    ((x number :default 0) (y number :default 0))
  "Move this block to a new (X Y) location."
  (save-location self)
  (when (and *quadtree* %quadtree-node)
    (quadtree-delete *quadtree* self))
  (setf %x x %y y)
  (when (and *quadtree* %quadtree-node)
    (quadtree-insert *quadtree* self)))

(define-method move-to-* block
    ((x number :default 0) 
     (y number :default 0)
     (z number :default 0))
  "Move this block to a new (X Y Z) location."
  (move-to self x y)
  (setf %z z))

(define-method move-toward block 
    ((direction symbol :default :up) (steps number :initform 1))
    "Move this block STEPS steps in the direction given by KEYWORD.
The KEYWORD must be one of:

 :up :down :left :right :upright :upleft :downleft :downright
"
  (with-field-values (x y) self
    (multiple-value-bind (x0 y0)
	(step-in-direction x y (or direction :up) (or steps 5))
      (move-to self x0 y0))))

(defun radian-angle (degrees)
  "Convert DEGREES to radians."
  (* degrees (float (/ pi 180))))

(define-method (turn-left :category :motion) block ((degrees number :default 90))
  "Turn this object's heading to the left DEGREES degrees."
  (decf %heading (radian-angle degrees)))

(define-method (turn-right :category :motion) block ((degrees number :default 90))
  "Turn this object's heading to the right DEGREES degrees."
  (incf %heading (radian-angle degrees)))

(defun step-coordinates (x y heading &optional (distance 1))
  (values (+ x (* distance (cos heading)))
	  (+ y (* distance (sin heading)))))

(define-method step-toward-heading block (heading &optional (distance 1))
  "Return as values the X,Y coordinate of the point DISTANCE units
away from this object, in the angle HEADING."
  (multiple-value-bind (x y) (center-point self)
    (step-coordinates x y heading distance)))

(define-method move-toward-heading block (heading &optional (distance 1))
  "Move this object DISTANCE units toward the angle HEADING."
  (multiple-value-bind (x0 y0) (step-coordinates %x %y heading distance)
    (move-to self x0 y0)))

(define-method move-forward block (distance)
  "Move this object DISTANCE units toward its current heading."
  (move-toward-heading self %heading distance))

(define-method move-backward block (distance)
  "Move this object DISTANCE units away from its current heading."
  (move-toward-heading self (- (* 2 pi) %heading distance)))

(defmacro save-excursion (object &body body)
  "Evaluate the forms in BODY, on OBJECT, saving the turtle
state (position and heading) and restoring them afterward."
  (let ((x (gensym))
	(y (gensym))
	(heading (gensym))
	(turtle (gensym)))
    `(let* ((,turtle ,object)
	    (,x (field-value :x ,turtle))
	    (,y (field-value :y ,turtle))
	    (,heading (field-value :heading ,turtle)))
       ,@body
       (move-to ,turtle ,x ,y)
       (setf (field-value :heading ,turtle) ,heading)
       (values ,x ,y ,heading))))

(define-method heading-to-thing block (thing)
  "Compute the heading angle from this object to the other object THING."
  (multiple-value-bind (x1 y1) (center-point thing)
    (multiple-value-bind (x0 y0) (center-point self)
      (find-heading x0 y0 x1 y1))))

(define-method heading-to-player block ()
  "Compute the heading angle from this object to the player."
  (heading-to-thing self (get-player *world*)))

;;; Visibility

(define-method show block ()
  (setf %visible t))

(define-method hide block ()
  (setf %visible nil))

(define-method toggle-visibility block ()
  (if %visible
      (hide self)
      (show self)))

(define-method visiblep block ()
  %visible)

;;; Menus and programming-blocks

;; See also library.lisp for the Message blocks.

(define-method make-method-menu-item block (method target)
  (assert (and target (keywordp method)))
  (let ((method-string (pretty-symbol-string method)))
    (list :label method-string
	  :method method
	  :target target
	  :action (new 'task method target))))

(define-method context-menu block ()
  (let ((methods nil)
	(pointer self))
    ;; gather methods
    (loop do
      (when (has-local-value :methods pointer)
	(setf methods 
	      (union methods 
			    (field-value :methods pointer))))
      (setf pointer (object-super pointer))
      while pointer)
    ;; 
    (let (inputs)
      (dolist (method (sort methods #'string<))
	(push (make-method-menu-item self method (find-uuid self)) inputs))
      (make-menu
       (list :label (concatenate 'string 
				 "Methods: "
				 (get-some-object-name self)
				 " " (object-address-string self))
	     :inputs (nreverse inputs)
	     :pinned nil
	     :expanded t
	     :locked t)
       :target (find-uuid self)))))

(define-method make-reference block ()
  (new 'reference self))

;;; Evaluation and recompilation: compiling block diagrams into equivalent sexps

(define-method evaluate-inputs block ()
  "Evaluate all blocks in %INPUTS from left-to-right. Results are
placed in corresponding positions of %RESULTS. Override this method
when defining new blocks if you don't want to evaluate all the inputs
all the time."
  (with-fields (inputs results) self
    (let ((arity (length inputs)))
      (when (< (length results) arity)
	(setf results (make-list arity)))
      (dotimes (n arity)
	(when (nth n inputs)
	  (setf (nth n results)
		(evaluate (nth n inputs))))))
    results))

(define-method evaluate block () 
  (eval (recompile self)))

(define-method recompile block ()
  `(progn 
     ,@(mapcar #'recompile %inputs)))

(defun count-tree (tree)
  "Return the number of blocks enclosed in this block, including the
current block. Used for taking a count of all the nodes in a tree."
  (cond ((null tree) 0)
	;; without inputs, just count the root
	((null (field-value :inputs tree)) 1)
	;; otherwise, sum up the counts of the children (if any)
	(t (apply #'+ 1 
		  (mapcar #'count-tree 
			  (field-value :inputs tree))))))

;;; Drawing blocks with complete theme customization

;; Very important for individuals with colorblindness.

(defparameter *background-color* "white"
  "The default background color of the BLOCKY user interface.")

(defparameter *socket-color* "gray80"
  "The default background color of block sockets.")

(defparameter *block-font* "sans-11"
  "Name of the font used in drawing block labels and input data.")

(defparameter *font* *block-font*
  "Name of the current font used for drawing.")

(defparameter *block-bold* "sans-bold-11")

(defmacro with-font (font &rest body)
  "Evaluate forms in BODY with FONT as the current font."
  `(let ((*font* ,font))
     ,@body))

(defparameter *sans* "sans-11"
  "Name of the default sans-serif font.")

(defparameter *serif* "serif-11"
  "Name of the default serif font.")

(defparameter *monospace* "sans-mono-10"
  "Name of the default monospace (fixed-width) font.")

(defvar *dash* 3
  "Size in pseudo-pixels of (roughly) the size of the space between
two words. This is used as a unit for various layout operations.
See also `*style'.")

(defun dash (&optional (n 1) &rest terms)
  "Return the number of pixels in N dashes. Add any remaining
arguments. Uses `*dash*' which may be configured by `*style*'."
  (apply #'+ (* n *dash*) terms))

(defvar *text-baseline* nil 
"Screen Y-coordinate for text baseline.
This is used to override layout-determined baselines in cases where
you want to align a group of text items across layouts.")

(defparameter *block-colors*
  '(:motion "cornflower blue"
    :system "black"
    :button "orange"
    :terminal "gray25"
    :event "gray80"
    :menu "gray10"
    :hover "red"
    :socket "gray60"
    :data "gray50"
    :structure "gray50"
    :comment "khaki1"
    :looks "purple"
    :sound "orchid"
    :message "sienna3"
    :control "orange1"
    :variables "DarkOrange2"
    :operators "OliveDrab3"
    :sensing "DeepSkyBlue3")
  "X11 color names of the different block categories.")

(defparameter *block-highlight-colors*
  '(:motion "sky blue"
    :system "black"
    :hover "dark orange"
    :button "gold"
    :event "gray90"
    :menu "gray30"
    :terminal "gray30"
    :comment "gray88"
    :looks "medium orchid"
    :socket "gray80"
    :data "gray80"
    :structure "gray60"
    :sound "plum"
    :message "sienna2"
    :control "gold"
    :variables "DarkOrange1"
    :operators "OliveDrab1"
    :sensing "DeepSkyBlue2")
  "X11 color names of highlights on the different block categories.")

(defparameter *block-shadow-colors*
  '(:motion "royal blue"
    :system "black"
    :event "gray70"
    :socket "gray90"
    :data "gray55"
    :menu "gray15"
    :terminal "gray21"
    :button "DarkOrange"
    :structure "gray35"
    :comment "gray70"
    :hover "orange red"
    :looks "dark magenta"
    :sound "violet red"
    :message "chocolate3"
    :control "dark orange"
    :variables "DarkOrange3"
    :operators "OliveDrab4"
    :sensing "steel blue")
  "X11 color names of shadows on the different block categories.")

(defparameter *block-foreground-colors*
  '(:motion "white"
    :system "white"
    :button "yellow"
    :event "gray40"
    :terminal "white"
    :comment "gray20"
    :socket "gray20"
    :hover "yellow"
    :data "white"
    :menu "white"
    :structure "white"
    :message "white"
    :looks "white"
    :sound "white"
    :control "white"
    :variables "white"
    :operators "white"
    :sensing "white")
  "X11 color names of the text used for different block categories.")

(define-method find-color block (&optional (part :background))
  "Return the X11 color name of this block's PART as a string.
If PART is provided, return the color for the corresponding
part (:BACKGROUND, :SHADOW, :FOREGROUND, or :HIGHLIGHT) of this
category of block."
  (let* ((colors (ecase part
		  (:background *block-colors*)
		  (:highlight *block-highlight-colors*)
		  (:shadow *block-shadow-colors*)
		  (:foreground *block-foreground-colors*)))
	 (category (if (keywordp %category) %category :system))
	 (result (getf colors category)))
      (prog1 result 
	(assert category)
	(assert result))))

(defparameter *selection-color* "red" 
  "Name of the color used for highlighting objects in the selection.")

(defparameter *styles* '((:rounded :dash 3)
			 (:flat :dash 1))
  "Graphical style parameters for block drawing.")

(defvar *style* :rounded "The default style setting; must be a keyword.")

(defmacro with-style (style &rest body)
  "Evaluate the forms in BODY with `*style*' bound to STYLE."
  (let ((st (gensym)))
  `(let* ((,st ,style)
	  (*style* ,st)
	  (*dash* (or (getf *styles* ,st)
		      *dash*)))
     ,@body)))

(defmacro with-block-drawing (&body body)
  "Run BODY forms with drawing primitives.
The primitives are CIRCLE, DISC, LINE, BOX, and TEXT. These are used
in subsequent functions as the basis of drawing nested diagrams of
blocks."
  `(let* ((foreground (find-color self :foreground))
	  (background (find-color self :background))
	  (highlight (find-color self :highlight))
	  (shadow (find-color self :shadow))
	  (radius (+ 6 *dash*))
	  (diameter (* 2 radius)))
     (labels ((circle (x y &optional color)
		(draw-circle x y radius
			     :color (or color background)
			     :blend :alpha))
	      (disc (x y &optional color)
		(draw-solid-circle x y radius
				   :color (or color background)
				   :blend :alpha))
	      (line (x0 y0 x1 y1 &optional color)
		(draw-line x0 y0 x1 y1
			   :color (or color background)))
	      (box (x y r b &optional color)
		(draw-box x y (- r x) (- b y)
			  :color (or color background)))
	      (text (x y string &optional color2)
		(draw-string string x 
			     (or *text-baseline* y)
			     :color (or color2 foreground)
			     :font *font*)))
       ,@body)))

(define-method draw-rounded-patch block (x0 y0 x1 y1
				    &key depressed dark socket color)
  "Draw a standard BLOCKY block notation patch with rounded corners.
Places the top left corner at (X0 Y0), bottom right at (X1 Y1). If
DEPRESSED is non-nil, draw an indentation; otherwise a raised area is
drawn. If DARK is non-nil, paint a darker region. If SOCKET is
non-nil, cut a hole in the block where the background shows
through. If COLOR is non-nil, its value will override all other
arguments."
  (with-block-drawing 
    (let ((bevel (or color (if depressed shadow highlight)))
	  (chisel (or color (if depressed highlight shadow)))
	  (fill (or color (if socket
			      *socket-color*
			      (if dark background background)))))
;      (disc (- x0 10) (- y0 10) fill) ;; a circle by itself
      ;; y1 x1
      (disc (- x1 radius ) (- y1 radius ) fill)
      (circle (- x1 radius ) (- y1 radius ) chisel) ;; chisel
      ;; y1 left
      (disc (+ x0 radius ) (- y1 radius ) fill)
      (circle (+ x0 radius ) (- y1 radius) chisel)
      ;; top left
      (disc (+ x0 radius ) (+ y0 radius) fill)
      (circle (+ x0 radius ) (+ y0 radius) bevel) ;;bevel
      ;; top x1
      (disc (- x1 radius ) (+ y0 radius ) fill)
      (circle (- x1 radius ) (+ y0 radius ) chisel) ;; chisel
      ;; y1 (bottom) 
      (box (+ x0 radius) (- y1 diameter)
	   (- x1 radius 1) y1
	   fill)
      (line (+ x0 radius -2) (1- y1)
	    (- x1 radius 1) y1 chisel)
      ;; top
      (box (+ x0 radius) y0
	   (- x1 radius) (+ y0 diameter)
	   fill)
      (line (+ x0 radius) (+ y0 0)
	    (- x1 radius -4) (+ y0 1) bevel)
      ;; left
      (box x0 (+ y0 radius)
	   (+ x0 diameter) (- y1 radius)
	   fill)
      (line (+ x0 1) (+ y0 radius)
	    (+ x0 1) (- y1 radius -3) bevel)
      ;; x1
      (box (- x1 diameter) (+ y0 radius)
	   x1 (- y1 radius)
	   fill)
      (line x1 (+ y0 radius)
	    x1 (- y1 radius) chisel)
      ;; content area
      (box (+ x0 radius) (+ y0 radius)
	   (- x1 radius) (- y1 radius)
	   fill)
      ;; cover seams
      (disc (- x1 radius 1) (- y1 radius 1) fill) ;; y1 x1
      (disc (+ x0 radius 1) (- y1 radius 1) fill) ;; y1 left
      (disc (+ x0 radius 1) (+ y0 radius 1) fill) ;; top left
      (disc (- x1 radius 1) (+ y0 radius 1) fill) ;; top x1
      )))

(define-method draw-flat-patch block (x0 y0 x1 y1
				    &key depressed dark socket color)
  "Draw a square-cornered Blocky notation patch. 
Places its top left corner at (X0 Y0), bottom right at (X1 Y1). If
DEPRESSED is non-nil, draw an indentation; otherwise a raised area is
drawn. If DARK is non-nil, paint a darker region."
  (with-block-drawing 
    (let ((bevel (or color (if depressed shadow highlight)))
	  (chisel (or color (if depressed highlight shadow)))
	  (fill (or color (if socket
			      *socket-color*
			      (if dark background background)))))
      ;; content area
      (box x0 y0  
	   x1 y1
	   fill)
      ;; bottom
      (line x0 y1 
	    x1 y1 
	    chisel)
      ;; top
      (line x0 y0
	    x1 y0 
	    bevel)
      ;; left
      (line x0 y0
	    x0 y1 
	    bevel)
      ;; right
      (line x1 y0
	    x1 y1 
	    chisel)
      )))

(define-method draw-patch block (x0 y0 x1 y1 
				    &key depressed dark socket color)
  "Draw a Blocky notation patch in the current `*style*'.
Places its top left corner at (X0 Y0), bottom right at (X1 Y1)."
  (let ((draw-function (ecase *style*
			 (:rounded #'draw-rounded-patch)
			 (:flat #'draw-flat-patch))))
    (funcall draw-function self
	     x0 y0 x1 y1 
	     :depressed depressed :dark dark 
	     :socket socket :color color)))

;;; Standard ways of blinking a cursor

(defparameter *cursor-blink-time* 8 
  "The number of frames the cursor displays each color while blinking.")

(defparameter *cursor-color* "magenta" 
  "The color of the cursor when not blinking.")

(defparameter *cursor-blink-color* "cyan"
  "The color of the cursor when blinking.")

(define-method update-cursor-clock block ()
  "Update blink timers for any blinking cursor indicators.
This method allows for configuring blinking items on a system-wide
scale. See also "
  (with-fields (cursor-clock) self
    (decf cursor-clock)
    (when (> (- 0 *cursor-blink-time*) cursor-clock)
      (setf cursor-clock *cursor-blink-time*))))

(define-method draw-cursor-glyph block
    (&optional (x 0) (y 0) (width 2) (height (font-height *font*))
	       &key color blink)
  "Draw a graphical cursor at point X, Y of dimensions WIDTH x HEIGHT."
  (with-fields (cursor-clock) self
    (let ((color2
	    (if blink
		(if (minusp cursor-clock)
		    *cursor-color*
		    *cursor-blink-color*)
		*cursor-color*)))
      (draw-box x y width height :color (or color color2)))))

(define-method draw-cursor block (&rest args)
  "Draw the cursor. By default, it is not drawn at all."
  (declare (ignore args))
  nil)

(defparameter *highlight-background-color* "gray40")

(defparameter *highlight-foreground-color* "gray10")

(define-method draw-focus block ()
  "Draw any additional indications of input focus." nil)

(define-method draw-highlight block () 
  "Draw any additional indications of mouseover." nil)

(defparameter *hover-color* "red" 
  "Name of the color used to indicate areas where objects can be
dropped.")

(define-method draw-hover block ()
  "Draw something to indicate that this object can recieve a drop.
See shell.lisp for more on the implementation of drag-and-drop."
  (with-fields (x y width height inputs) self
    (draw-patch self x y (+ x *dash* width) (+ y *dash* height)
	      :color *hover-color*)
    (dolist (input inputs)
      (draw input))))

(define-method resize-to-image block ()
  (with-fields (image height width) self
    (when image
      (setf width (image-width image)))
      (setf height (image-height image))))

;; (define-method draw-as-sprite block ()
;;   "Draw this block as a sprite. By default only %IMAGE is drawn.
;; The following block fields will control sprite drawing:

;;    %OPACITY  Number in the range 0.0-1.0 with 0.0 being fully transparent
;;              and 1.0 being fully opaque.

;;    %BLEND    Blending mode for OpenGL compositing.
;;              See the function `set-blending-mode' for a list of modes."
;;   (with-fields (image x y z height opacity blend) self
;;     (when image
;;       (when (null height)
;; 	(resize-to-image self))
;;       (draw-image image x y :z z 
;; 			    :opacity opacity 
;; 			    :blend blend))))

(define-method scale block (x-factor &optional y-factor)
  (let ((image (find-resource-object %image)))
    (resize self 
	    (* (sdl:width image) x-factor)
	    (* (sdl:height image) (or y-factor x-factor)))))

(define-method change-image block 
    ((image string :default nil))
  "Change this sprite's currently displayed image to IMAGE, resizing
the object if necessary."
  (when image
    (setf %image image)
    (resize-to-image self)))
  
(define-method draw block ()
  "Draw this block via OpenGL commands. "
  (with-fields (image x y width height blend opacity) self
    (if image 
	(draw-image image x y 
		    :blend blend :opacity opacity
		    :height height :width width)
	(progn (draw-patch self x y (+ x width) (+ y height))
	       (mapc #'draw %inputs)))))

(define-method draw-border block (&optional (color *selection-color*))
  (let ((dash *dash*))
    (with-fields (x y height width) self
      (draw-patch self (- x dash) (- y dash)
		   (+ x width dash)
		   (+ y height dash)
		   :color color))))

(define-method draw-background block ()
  (with-fields (x y width height) self
    (draw-patch self x y (+ x width) (+ y height))))

(define-method draw-ghost block ()
  (with-fields (x y width height) self
    (draw-patch self x y (+ x width) (+ y height)
		 :depressed t :socket t)))

(define-method header-height block () 0)

(define-method header-width block () %width)

(defparameter *socket-width* (* 18 *dash*))

(defun print-expression (expression)
  (assert (not (object-p expression)))
  (string-downcase
   (typecase expression
     (symbol
	(substitute #\Space #\- (symbol-name expression)))
     (otherwise (format nil "~s" expression)))))

(defun expression-width (expression &optional (font *font*))
  (if (blocky:object-p expression)
      *socket-width*
      (font-text-width (print-expression expression) font)))

(define-method set-label-string block (label)
  (assert (stringp label))
  (setf %label label))

(define-method label-string block ()
  %label)

(define-method label-width block ()
  (if (null %label)
      0
      (+ (dash 2)
	 (font-text-width %label *block-font*))))
    
(define-method draw-label-string block (string &optional color)
  (with-block-drawing 
    (with-field-values (x y) self
      (let* ((dash *dash*)
	     (left (+ x (* 2 dash)))
	     (y0 (+ y dash 1)))
	(text left y0 string color)))))

(define-method draw-label block (expression)
  (draw-label-string self (print-expression expression)))

;;; Layout management

(define-method center block ()
  "Automatically center the block on the screen."
  (with-fields (window-x window-y) *world*
    (with-fields (x y width height) self
      (let ((center-x (+ window-x (/ *gl-screen-width* 2)))
	    (center-y (+ window-y (/ *gl-screen-height* 2))))
	(setf x (+ (- center-x (/ width 2))))
	(setf y (+ (- center-y (/ width 2))))))))

(define-method center-as-dialog block ()
  (center self)
  (align-to-pixels self))

(define-method pin block ()
  "Prevent dragging and moving of this block."
  (setf %pinned t))

(define-method unpin block () 
  "Allow dragging and moving of this block."
  (setf %pinned nil))

(define-method pinnedp block ()
  "When non-nil, dragging and moving are disallowed for this block."
  %pinned)

(define-method resize block 
    ((width number :default 100)
     (height number :default 100))
  "Change this object's size to WIDTH by HEIGHT units."
  (when %quadtree-node (quadtree-delete *quadtree* self))
  (setf %height height)
  (setf %width width)
  (when *quadtree* (quadtree-insert *quadtree* self))
  (invalidate-layout self))

(define-method layout block () 
  (if %image 
      (resize-to-image self)
      (with-fields (height width label) self
	(with-field-values (x y inputs) self
	  (let* ((left (+ x (label-width self)))
		 (max-height (font-height *font*))
		 (dash (dash 1)))
	    (dolist (input inputs)
	      (move-to input (+ left dash) y)
	      (layout input)
	      (setf max-height (max max-height (field-value :height input)))
	      (incf left (dash 1 (field-value :width input))))
	    ;; now update own dimensions
	    (setf width (dash 1 (- left x)))
	    (setf height (+  (if (null inputs)
				     dash 0) max-height)))))))

;;; Sound 

(define-method play-sound block 
    ((name string :default "chirp"))
    "Play the sample named NAME."
  (play-sample name))

;;; Collision detection and UI hit testing

(define-method hit block (mouse-x mouse-y)
  "Return this block (or child input block) if the coordinates MOUSE-X
and MOUSE-Y identify a point inside the block (or input block.)"
  (with-fields (x y width height inputs) self
    (when (within-extents mouse-x mouse-y x y
			  (+ x width) (+ y height))
      (labels ((try (it)
		 (hit it mouse-x mouse-y)))
	(or (some #'try inputs) 
	    self)))))

(define-method bounding-box block ()
  "Return this object's bounding box as multiple values.
The order is (TOP LEFT RIGHT BOTTOM)."
  (when (null %height)
    (resize-to-image self))
  (values %y %x (+ %x %width) (+ %y %height)))

(define-method center-point block ()
  "Return this object's center point as multiple values X and Y."
  (multiple-value-bind (top left right bottom)
      (bounding-box self)
    (values (* 0.5 (+ left right))
	    (* 0.5 (+ top bottom)))))

(define-method at block ()
  (values %x %y))

(define-method left-of block (&optional other)
  (let ((width (field-value :width (or other self))))
    (values (- %x width) %y)))
  
(define-method right-of block ()
  (values (+ %x %width) %y))

(define-method above block (&optional other)
  (let ((height (field-value :height (or other self))))
    (values (- %x %width) %y)))
  
(define-method below block ()
  (values %x (+ %y %height)))

(define-method left-of-center block (&optional other)
  (multiple-value-bind (x y) (left-of self other)
    (values x (+ y (/ %height 2)))))

(define-method right-of-center block ()
  (multiple-value-bind (x y) (left-of-center self)
    (values (+ x %width) y)))

(define-method above-center block (&optional other)
  (multiple-value-bind (x y) (above self other)
    (values (+ x (/ %width 2)) y)))

(define-method below-center block ()
  (multiple-value-bind (x y) 
      (above-center self)
    (values x (+ y %height))))

(define-method collide block (object)
  (declare (ignore object))
  "Respond to a collision detected with OBJECT. The default implementation does nothing."
  nil)

(defun point-in-rectangle-p (x y width height o-top o-left o-width o-height)
  (let ((o-right (+ o-left o-width))
	(o-bottom (+ o-top o-height)))
    (not (or 
	  ;; is the top below the other bottom?
	  (<= o-bottom y)
	  ;; is bottom above other top?
	  (<= (+ y height) o-top)
	  ;; is right to left of other left?
	  (<= (+ x width) o-left)
	  ;; is left to right of other right?
	  (<= o-right x)))))

(define-method colliding-with-rectangle block (o-top o-left o-width o-height)
  ;; you must pass arguments in Y X order since this is TOP then LEFT
  (with-fields (x y width height) self
    (point-in-rectangle-p x y width height o-top o-left o-width o-height)))

(define-method colliding-with-bounding-box block (bounding-box)
  ;; you must pass arguments in Y X order since this is TOP then LEFT
  (with-fields (x y width height) self
    (destructuring-bind (top left right bottom) bounding-box
      (point-in-rectangle-p x y width height top left (- right left) (- bottom top)))))

(define-method colliding-with block (thing)
  "Return non-nil if this block collides with THING."
  (multiple-value-bind (top left right bottom)
      (bounding-box self)
    (multiple-value-bind (top0 left0 right0 bottom0)
	(bounding-box thing)
      (and (<= left right0)
	   (>= right left0)
	   (<= top bottom0)
	   (>= bottom top0)))))

(define-method direction-to-thing block (thing)
  "Return a direction keyword approximating the direction to THING."
  (with-fields (x y) thing
    (direction-to %x %y x y)))

(define-method direction-to-player block ()
  "Return the directional keyword naming the general direction to the player."
  (direction-to-thing self (get-player *world*)))

(define-method heading-to-thing block (thing)
  "Return a heading (in radians) to THING."
  (with-fields (x y) thing
    (find-heading %x %y x y)))

(define-method heading-to-player block ()
  "The heading (in radians) to the player from this block."
  (heading-to-thing self (get-player *world*)))

(define-method aim-at-thing block (thing)
  "Aim the current heading at the object THING."
  (setf %heading (heading-to-thing self thing)))

(define-method aim block (heading)
  "Aim this object toward the angle HEADING."
  (assert (numberp heading))
  (setf %heading heading))

(define-method distance-to-thing block (thing)
  "Return the straight-line distance between here and THING.
Note that the center-points of the objects are used for comparison."
  (multiple-value-bind (x0 y0) (center-point self)
    (multiple-value-bind (x y) (center-point thing)
      (distance x0 y0 x y))))

(define-method distance-to-player block ()
  "Return the straight-line distance to the player."
  (distance-to-thing self (get-player *world*)))

;; (defun uniquify-buffer-name (name)
;;   (let ((n 1)
;; 	(name0 name))
;;     (block naming
;;       (loop while name0 do
;; 	(if (get-buffer name0)
;; 	    (setf name0 (format nil "~A.~S" name n)
;; 		  n (1+ n))
;; 	    (return-from naming name0))))))

(define-method queue-layout block ()
  (setf %needs-layout t))

(define-method invalidate-layout block ()
  (let ((world (world)))
    (when (and world (has-method :queue-layout world))
      (queue-layout world))))

(define-method bring-to-front block (block)
  (with-fields (inputs) self
    (assert (contains self block))
    (delete-input self block)
    (append-input self block)))

;; (define-method update block ()
;;   (with-buffer self 
;;     (dolist (each %inputs)
;;       (update each))
;;     (update-layout self)))

(define-method update-layout block (&optional force)
  (with-fields (inputs needs-layout) self
    (when (or force needs-layout)
      (dolist (each inputs)
	(layout each))
      (setf needs-layout nil))))

(define-method append-input block (block)
  (assert (blockyp block))
  (with-fields (inputs) self
    (assert (not (contains self block)))
    (set-parent block self)
    (setf inputs (nconc inputs (list block)))))

(define-method add-block block (block &optional x y)
  (assert (blockyp block))
  ;(assert (not (contains self block)))
  (append-input self block)
  (when (and (integerp x)
	     (integerp y))
    (move-to block x y))
  (save-location block)
  (invalidate-layout self))

(define-method delete-block block (block)
  (assert (blockyp block))
  (assert (contains self block))
  (delete-input self block))

;;; Simple scheduling mechanisms

(define-block task method target arguments clock subtasks finished)

(define-method initialize task 
    (method target 
	    &key arguments clock subtasks)
  (assert method)
  (assert (listp arguments))
  (assert (blockyp target))
  (assert (or (eq t clock)
	      (null clock)
	      (and (integerp clock)
		   (plusp clock))))
  (setf %method (make-keyword method)
	%arguments arguments
	%target (find-uuid target)
	%subtasks subtasks
	%clock clock))

(define-method finish task ()
  (setf %finished t))

(define-method evaluate task ()
  (apply #'send %method %target %arguments))

(define-method running task ()
  (with-fields (method target arguments clock finished) self
    (cond 
      ;; if finished, quit now.
      (finished nil)
      ;; countdown exists and is finished.
      ((and (integerp clock)
	    (zerop clock))
       (prog1 nil (evaluate self)))
      ;; countdown not finished. tell manager to keep running, 
      ;; but don't evaluate at this time
      ((and (integerp clock)
	    (plusp clock))
       (prog1 t 
	 (decf clock)))
      ;; no countdown, but we should test the output.
      ;; if non-nil, manager keeps us running.
      ((eq t clock)
       (let ((result (evaluate self)))
	 (prog1 result
	   (if result
	       (mapc #'running %subtasks)
	       (mapc #'finish %subtasks)))))
      ;; no countdown or testing. just keep running.
      ((null clock)
       (prog1 t (evaluate self)))
      ;; shouldn't reach here
      (t (error "Invalid task.")))))

(defun seconds->frames (seconds)
  (truncate (* seconds (/ 1000 *dt*))))

(defun time-until (updates)
  (assert (>= updates *updates*))
  (- updates *updates*))
  
(defun time-as-frames (value)
  (etypecase value
    (integer value)
    (float (seconds->frames value))))

(defun make-task-form (delay expression &optional subexpressions)
  (destructuring-bind (method target &rest arguments) expression
    (let ((target-sym (gensym))
	  (delay-sym (gensym)))
      `(let ((,target-sym ,target)
	     (,delay-sym ,delay))
	 (add-task ,target-sym
		   (new 'task 
			,(make-keyword method)
			,target-sym
			:subtasks (list ,@(make-tasks delay-sym subexpressions))
			:arguments (list ,@arguments)
			:clock ,delay))))))

(defun make-tasks (delay forms)
  (mapcar #'(lambda (form)
	      (make-task-form delay form))
	  forms))

(defmacro later (delay &rest forms)
  (assert (every #'consp forms))
  (let ((clock (time-as-frames delay))) 
    `(progn ,@(make-tasks clock forms))))

(defmacro later-at (absolute-time &body forms)
  `(later ,(time-until absolute-time) ,@forms))

(defmacro later-while (test-expression &body subtask-expressions)
  `(later ,(make-task-form t test-expression subtask-expressions)))

;; see also library.lisp for more block examples and many basic blocks

;;; blocks.lisp ends here
 
