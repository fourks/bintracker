
;; This file is part of Bintracker NG.
;; Copyright (c) utz/irrlicht project 2019
;; See LICENSE for license details.

;; -----------------------------------------------------------------------------
;;; # Bintracker GUI abstractions
;; -----------------------------------------------------------------------------


(module bt-gui
    *

  (import scheme (chicken base) (chicken pathname)
	  srfi-1 srfi-13
	  defstruct matchable simple-exceptions pstk
	  bt-state bt-types mdal)

  ;; ---------------------------------------------------------------------------
  ;;; ### PS/Tk Initialization
  ;; ---------------------------------------------------------------------------

  ;;; Init pstk and fire up Tcl/Tk runtime.
  ;;; This must be done prior to defining anything that depends on Tk.

  (tk-start)

  ;; disable "tearoff" style menus
  (tk-eval "option add *tearOff 0")

  ;; automatically map the following tk widgets to their ttk equivalent
  (ttk-map-widgets '(button checkbutton radiobutton menubutton label frame
			    labelframe scrollbar notebook panedwindow
			    progressbar combobox separator scale sizegrip
			    spinbox treeview))


  ;; ---------------------------------------------------------------------------
  ;;; ### Dialogues
  ;; ---------------------------------------------------------------------------

  ;;; Various general-purpose dialogue (tk message-box) procedures.

  (define (about-message)
    (tk/message-box title: "About"
		    message: (string-append "Bintracker\nversion "
					    *bintracker-version*)
		    type: 'ok))

  ;;; Display a message box that asks the user whether to save unsaved changes
  ;;; before exiting or closing. **exit-or-closing** should be the string
  ;;; `"exit"` or `"closing"`, respectively.
  (define (exit-with-unsaved-changes-dialog exit-or-closing)
    (tk/message-box title: (string-append "Save before " exit-or-closing "?")
		    default: 'yes
		    icon: 'warning
		    parent: tk
		    message: (string-append "There are unsaved changes. "
					    "Save before " exit-or-closing "?")
		    type: 'yesnocancel))


  ;; ---------------------------------------------------------------------------
  ;;; ### Images
  ;; ---------------------------------------------------------------------------

  ;;; Auxilliary image handling procedures.

  ;;; Create a tk image resource from a given PNG file.
  (define (tk/icon filename)
    (tk/image 'create 'photo format: "PNG"
	      file: (string-append "resources/icons/" filename)))


  ;; ---------------------------------------------------------------------------
  ;;; ### Menus
  ;; ---------------------------------------------------------------------------

  ;;; `submenus` shall be an alist, where keys are unique identifiers, and
  ;;; values are the actual tk menus.
  (defstruct menu
    widget (items '()))

  ;;; Destructively add an item to menu-struct **menu** according to
  ;;; **item-spec**. **item-spec** must be a list containing either
  ;;; ('separator)
  ;;; ('command id label underline accelerator command)
  ;;; ('submenu id label underline items-list)
  ;;; where *id*  is a unique identifier symbol; *label* and *underline* are the
  ;;; name that will be shown in the menu for this item, and its underline
  ;;; position; *accelerator* is a string naming a keyboard shortcut for the
  ;;; item, command is a procedure to be associated with the item, and
  ;;; items-list is a list of item-specs.
  ;; TODO add at position (insert)
  (define (add-menu-item! menu item-spec)
    (let ((append-to-item-list!
	   (lambda (id item)
	     (menu-items-set! menu (append (menu-items menu)
					   (list id item))))))
      (match (car item-spec)
	('command (begin
		    (append-to-item-list! (second item-spec) #f)
		    ((menu-widget menu) 'add 'command label: (third item-spec)
		     underline: (fourth item-spec)
		     accelerator: (or (fifth item-spec) "")
		     command: (sixth item-spec))))
	('submenu (let* ((submenu (construct-menu (fifth item-spec))))
		    (append-to-item-list! (second item-spec)
					  submenu)
		    ((menu-widget menu) 'add 'cascade
		     menu: (menu-widget submenu)
		     label: (third item-spec)
		     underline: (fourth item-spec))))
	('separator (begin
		      (append-to-item-list! 'separator #f)
		      ((menu-widget menu) 'add 'separator)))
	(else (error (string-append "Unknown menu item type \""
				    (->string (car item-spec))
				    "\""))))))

  (define (construct-menu items)
    (let* ((my-menu (make-menu widget: (tk 'create-widget 'menu))))
      (for-each (lambda (item)
		  (add-menu-item! my-menu item))
		items)
      my-menu))


  ;; ---------------------------------------------------------------------------
  ;;; ## Top Level Layout
  ;; ---------------------------------------------------------------------------

  ;;; The core widgets that make up Bintracker's GUI.

  (define top-frame (tk 'create-widget 'frame 'padding: "0 0 0 0"))

  (define toolbar-frame (top-frame 'create-widget 'frame 'padding: "0 1 0 1"))

  (define edit-settings-frame (top-frame 'create-widget 'frame))

  (define main-panes (top-frame 'create-widget 'panedwindow))

  (define main-frame (main-panes 'create-widget 'frame))

  (define console-frame (main-panes 'create-widget 'frame))

  (define status-frame (top-frame 'create-widget 'frame))

  (define (init-top-level-layout)
    (begin
      (tk/pack status-frame fill: 'x side: 'bottom)
      (tk/pack top-frame expand: 1 fill: 'both)
      (tk/pack toolbar-frame expand: 0 fill: 'x)
      (tk/pack (top-frame 'create-widget 'separator orient: 'horizontal)
	       expand: 0 fill: 'x)
      (show-edit-settings)
      (tk/pack edit-settings-frame expand: 0 'fill: 'x)
      (tk/pack main-panes expand: 1 fill: 'both)
      (main-panes 'add main-frame weight: 5)
      (main-panes 'add console-frame weight: 2)))

  ;; TODO take into account which zones are actually active
  ;;; The list of all ui zones that can be focussed. The list consists of a list
  ;;; for each zone, which contains the focus procedure in car, and the unfocus
  ;;; procedure in cadr.
  (define ui-zone-focus-procs
    (list (list (lambda () (focus-fields-widget (current-fields-view)))
		(lambda () (unfocus-fields-widget (current-fields-view))))
	  (list (lambda () (focus-metatree (current-blocks-view)))
		(lambda () (unfocus-metatree (current-blocks-view))))
	  (list (lambda () (focus-metatree (current-order-view)))
		(lambda () (unfocus-metatree (current-order-view))))
	  (list (lambda () (tk/focus console))
		(lambda () '()))))

  (define (switch-ui-zone-focus current-zone-index new-zone-index)
    ((cadr (list-ref ui-zone-focus-procs current-zone-index)))
    (set-state! 'current-ui-zone new-zone-index)
    ((car (list-ref ui-zone-focus-procs new-zone-index))))

  (define (focus-next-ui-zone)
    (let* ((current-zone (state 'current-ui-zone))
	   (next-zone (if (= current-zone (sub1 (length ui-zone-focus-procs)))
			  0 (+ 1 current-zone))))
      (switch-ui-zone-focus current-zone next-zone)))

  (define (focus-previous-ui-zone)
    (let* ((current-zone (state 'current-ui-zone))
	   (prev-zone (if (= current-zone 0)
			  (sub1 (length ui-zone-focus-procs))
			  (sub1 current-zone))))
      (switch-ui-zone-focus current-zone prev-zone)))


  ;; ---------------------------------------------------------------------------
  ;;; ## Edit Settings Display
  ;; ---------------------------------------------------------------------------

  ;;; Display a label widget as description of an edit setting spinbox
  (define (pack-edit-settings-label text description)
    (let ((label (edit-settings-frame 'create-widget 'label text: text)))
      (tk/pack label side: 'left padx: 5)
      (bind-info-status label description)))

  ;;; Create a spinbox in the edit settings toolbar.
  ;;; {{from}} and {{to}} specify the permitted range of values,
  ;;; {{default-setting}} specifies an entry in `app-settings`, and
  ;;; {{validate-command}}/{{invalid-command}} specify the commands called by
  ;;; the spinbox widget on validation and validation failure. Validation
  ;;; occurs on `focusout`.
  ;; TODO perhaps validating on focusout is not the best option?
  (define (make-edit-settings-spinbox from to validate-command
				      invalid-command)
    (edit-settings-frame 'create-widget 'spinbox from: from to: to width: 4
			 state: 'disabled validate: 'focusout
			 validatecommand: validate-command
			 invalidcommand: invalid-command))

  (define edit-settings
    (letrec ((edit-step-spinbox
	      (make-edit-settings-spinbox
	       0 64
	       (lambda ()
		 (let* ((newval (string->number (edit-step-spinbox 'get)))
			(valid? (and (integer? newval)
				     (>= newval 0)
				     (<= newval 64))))
		   (when valid? (set-state! 'edit-step newval))
		   valid?))
	       (lambda ()
		 (edit-step-spinbox 'set (state 'edit-step))))))
      `((edit-step "Step" "Set the edit step" default-edit-step
		   ,edit-step-spinbox)
	(base-octave "Octave" "Set the base octave" default-base-octave
		     ,(make-edit-settings-spinbox 0 9 (lambda () #t)
						  (lambda () #t)))
	(major-highlight "Major Row" "Set the major row highlight"
			 default-major-row-highlight
			 ,(make-edit-settings-spinbox 2 64 (lambda () #t)
						      (lambda () #t)))
	(minor-highlight "Minor Row" "Set the minor row highlight"
			 default-minor-row-highlight
			 ,(make-edit-settings-spinbox 2 32 (lambda () #t)
						      (lambda () #t))))))

  ;;; Set the state of the edit settings spinboxes to {{state}}, which must be
  ;;; either `'enabled` or `'disabled`.
  (define (set-edit-settings-state! state)
    (for-each (lambda (setting)
		((fifth setting) 'configure state: state))
	      edit-settings))

  ;;; Enable the edit settings spinboxes.
  (define (enable-edit-settings!)
    (set-edit-settings-state! 'enabled))

  ;;; Disable the edit settings spinboxes.
  (define (disable-edit-settings!)
    (set-edit-settings-state! 'disabled))

  ;;; Display the edit settings in the main GUI.
  (define (show-edit-settings)
    (for-each (lambda (setting)
		(pack-edit-settings-label (cadr setting) (third setting))
		(tk/pack (fifth setting) side: 'left)
		((fifth setting) 'set (settings (fourth setting))))
	      edit-settings))


  ;; ---------------------------------------------------------------------------
  ;;; ## Console
  ;; ---------------------------------------------------------------------------

  (define console-wrapper (console-frame 'create-widget 'frame))

  ;; TODO color styling should be done in bt-state or bt-gui
  (define console (console-wrapper 'create-widget 'text blockcursor: 'yes))

  (define console-yscroll (console-wrapper 'create-widget 'scrollbar
					   orient: 'vertical))

  (define (init-console)
    (tk/pack console-wrapper expand: 1 fill: 'both)
    (tk/pack console expand: 1 fill: 'both side: 'left)
    (tk/pack console-yscroll side: 'right fill: 'y)
    (console-yscroll 'configure command: `(,console yview))
    (console 'configure 'yscrollcommand: `(,console-yscroll set))
    (console 'insert 'end
	     (string-append "Bintracker " *bintracker-version*
			    "\n(c) 2019 utz/irrlicht project\n"
			    "Ready.\n")))

  (define (clear-console)
    (console 'delete 0.0 'end))

  ;; ---------------------------------------------------------------------------
  ;;; Style updates
  ;; ---------------------------------------------------------------------------

  (define (patch-tcltk-8.6.9-treeview)
    (when (string= "8.6.9" (tk-eval "info patchlevel"))
      (ttk/style 'map 'Metatree.Treeview foreground:
		 '(disabled SystemGrayText selected SystemHighlightText)
		 background: '(disabled SystemButtonFace selected
					SystemHighlightText))))

  ;; TODO also update other metawidget colors here
  (define (update-style!)
    (ttk/style 'configure 'Metatree.Treeview background: (colors 'background)
	       fieldbackground: (colors 'background)
	       foreground: (colors 'text)
	       font: (list family: (settings 'font-mono)
			   size: (settings 'font-size))
	       rowheight: (get-treeview-rowheight))

    ;; hide treeview borders
    (ttk/style 'layout 'Metatree.Treeview '(Treeview.treearea sticky: nswe))
    (ttk/style 'configure 'Metatree.Treeview.Item indicatorsize: 0)

    (ttk/style 'configure 'BT.TFrame background: (colors 'background))

    (ttk/style 'configure 'BT.TLabel background: (colors 'background)
	       foreground: (colors 'text)
	       font: (list family: (settings 'font-mono)
			   size: (settings 'font-size)
			   weight: 'bold))

    (ttk/style 'configure 'BT.TNotebook background: (colors 'background))
    (ttk/style 'configure 'BT.TNotebook.Tab
	       background: (colors 'background)
	       font: (list family: (settings 'font-mono)
			   size: (settings 'font-size)
			   weight: 'bold))

    (console 'configure bg: (colors 'background))
    (console 'configure fg: (colors 'text))
    (console 'configure insertbackground: (colors 'text)))


  ;; ---------------------------------------------------------------------------
  ;;; ## Status Bar
  ;; ---------------------------------------------------------------------------

  ;;; Initialize the status bar at the bottom of the main window.
  (define (init-status-bar)
    (let ((status-label (status-frame 'create-widget 'label
				      textvariable: (tk-var "status-text"))))
      (reset-status-text!)
      (tk/pack status-label fill: 'x side: 'left)
      (tk/pack (status-frame 'create-widget 'sizegrip) side: 'right)))

  (define (get-module-info-text)
    (string-append (if (current-mod)
		       (string-append
  			(md:target-id (md:config-target (current-config)))
  			" | " (md:mod-cfg-id (current-mod)))
		       "No module loaded.")
		   " | "))

  ;;; Set the message in the status to either a combination of the current
  ;;; module's target platform and configuration name, or the string
  ;;; "No module loaded."
  (define (reset-status-text!)
    (tk-set-var! "status-text" (string-append (get-module-info-text)
					      (state 'active-md-command-info))))

  ;;; Display {{msg}} in the status bar, extending the current info string.
  (define (display-action-info-status! msg)
    (tk-set-var! "status-text" (string-append (get-module-info-text)
					      msg)))

  ;;; Bind the `<Enter>`/`<Leave>` events for the given {{widget}} to display/
  ;;; remove the given info {{text}} in the status bar.
  (define (bind-info-status widget text)
    (tk/bind widget '<Enter>
	     (lambda () (display-action-info-status! text)))
    (tk/bind widget '<Leave> reset-status-text!))

  ;;; Construct an info string for the key binding of the given action in the
  ;;; given key-group
  (define (key-binding->info key-group action)
    (let ((binding (inverse-key-binding key-group action)))
      (if binding
	  (string-upcase (string-translate (->string binding) "<>" "()"))
	  "")))

  ;; ---------------------------------------------------------------------------
  ;;; ## Module Display Related Widgets and Procedures
  ;; ---------------------------------------------------------------------------

  ;;; The module display is constructed as follows:
  ;;;
  ;;; Within the module display frame provided by Bintracker's top level layout,
  ;;; a `bt-group-widget` is constructed, and the GLOBAL group is associated
  ;;; with it. The `bt-group-widget` meta-widget consists of a Tk frame, which
  ;;; optionally creates a `bt-fields-widget`, a `bt-blocks-widget`, and a
  ;;; `bt-subgroups-widget` as children, for the group's fields, blocks, and
  ;;; subgroups, respectively.
  ;;;
  ;;; The `bt-fields-widget` consists of a Tk frame, which packs one or more
  ;;; `bt-field-widget` meta-widgets. A `bt-field-widget` consists of a Tk frame
  ;;; that contains a label displaying the field ID, and an input field for the
  ;;; associated value. `bt-fields-widget` and its children are only used for
  ;;; group fields, block fields are handled differently.
  ;;;
  ;;; The `bt-blocks-widget` consists of a ttk::panedwindow, containing 2 panes.
  ;;; The first pane contains the actual block display (all of the parent
  ;;; group's block members except the order block displayed next to each
  ;;; other), and the second pane contains the order or block list display.
  ;;; Both the block display and the order display are based on the `metatree`
  ;;; meta-widget, which is documented below.
  ;;;
  ;;; The `bt-subgroups-widget` consists of a Tk frame, which packs a Tk
  ;;; notebook (tab view), with tabs for each of the parent node's subgroups.
  ;;; A Tk frame is created in each of the tabs. For each subgroup, a
  ;;; `bt-group-widget` is created as a child of the corresponding tab frame.
  ;;; This allows for infinite nested groups, as required by MDAL.
  ;;;
  ;;; All `bt-*` widgets should be created by calling the corresponding
  ;;; `make-*-widget` procedures (named after the underlying `bt-*` structs, but
  ;;; dropping the `bt-*` prefix. Widgets should be packed to the display by
  ;;; calling the corresponding `show-*-widget` procedures.


  ;; ---------------------------------------------------------------------------
  ;;; ### Auxilliary procedures used by various BT meta-widgets
  ;; ---------------------------------------------------------------------------

  ;;; Determine how many characters are needed to print values of a given
  ;;; command.
  ;; TODO results should be cached
  (define (value-display-size command-config)
    (match (md:command-type command-config)
      ;; FIXME this is incorrect for negative numbers
      ((or 'int 'uint) (inexact->exact
			(ceiling
			 (/ (log (expt 2 (md:command-bits command-config)))
			    (log (settings 'number-base))))))
      ((or 'key 'ukey) (if (memq 'is_note (md:command-flags command-config))
			   3 (apply max
				    (map (o string-length car)
					 (hash-table-keys
					  (md:command-keys command-config))))))
      ('reference (if (>= 16 (settings 'number-base))
		      2 3))
      ('trigger 1)
      ('string 32)))

  ;;; Transform an ifield value from MDAL format to tracker display format.
  ;;; Replaces empty values with dots, changes numbers depending on number
  ;;; format setting, and turns everything into a string.
  (define (normalize-field-value val field-id)
    (let ((command-config (md:config-get-inode-source-command
  			   field-id (current-config))))
      (if (null? val)
	  (list->string (make-list (value-display-size command-config)
  	  			   #\.))
  	  (match (md:command-type command-config)
	    ((or 'int 'uint 'reference)
	     (string-pad (number->string val (settings 'number-base))
			 (value-display-size command-config)
			 #\0))
	    ((or 'key 'ukey) (if (memq 'is_note
				       (md:command-flags command-config))
				 (md:normalize-note-name val)
				 val))
	    ('trigger "x")
	    ('string val)))))

  ;;; Get the RGB color string associated with the field's command type.
  (define (get-field-color field-id)
    (let ((command-config (md:config-get-inode-source-command
			   field-id (current-config))))
      (if (memq 'note (md:command-flags command-config))
	  (colors 'text-1)
	  (match (md:command-type command-config)
	    ((or 'int 'uint) (colors 'text-2))
	    ((or 'key 'ukey) (colors 'text-3))
	    ('reference (colors 'text-4))
	    ('trigger (colors 'text-5))
	    ('string (colors 'text-6))
	    ('modifier (colors 'text-7))
	    (else (colors 'text))))))

  ;; ---------------------------------------------------------------------------
  ;;; ### Field-Related Widgets and Procedures
  ;; ---------------------------------------------------------------------------

  ;;; A meta widget for displaying an MDAL group field.
  (defstruct bt-field-widget toplevel-frame id-label val-entry node-id)

  ;;; Create a `bt-field-widget`.
  (define (make-field-widget node-id parent-widget)
    (let ((tl-frame (parent-widget 'create-widget 'frame style: 'BT.TFrame))
	  (color (get-field-color node-id)))
      (make-bt-field-widget
       toplevel-frame: tl-frame
       node-id: node-id
       id-label: (tl-frame 'create-widget 'label style: 'BT.TLabel
			   foreground: color text: (symbol->string node-id))
       val-entry: (tl-frame 'create-widget 'entry
			    bg: (colors 'row-highlight-minor) fg: color
			    bd: 0 highlightthickness: 0 insertborderwidth: 1
			    justify: 'center
			    font: (list family: (settings 'font-mono)
					size: (settings 'font-size))))))

  ;;; Display a `bt-field-widget`.
  (define (show-field-widget w group-instance-path)
    (tk/pack (bt-field-widget-toplevel-frame w)
	     side: 'left)
    (tk/pack (bt-field-widget-id-label w)
	     (bt-field-widget-val-entry w)
	     side: 'top padx: 4 pady: 4)
    ((bt-field-widget-val-entry w) 'insert 'end
     (normalize-field-value (md:inode-instance-val
    			     ((md:node-instance-path
    			       (string-append
    				group-instance-path
    				(symbol->string (bt-field-widget-node-id w))
    				"/0/"))
    			      (md:mod-global-node (current-mod))))
    			    (bt-field-widget-node-id w))))

  (define (focus-field-widget w)
    (let ((entry (bt-field-widget-val-entry w)))
      (entry 'configure bg: (colors 'cursor))
      (tk/focus entry)))

  (define (unfocus-field-widget w)
    ((bt-field-widget-val-entry w) 'configure bg: (colors 'row-highlight-minor)))

  ;;; A meta widget for displaying an MDAL group's field members.
  (defstruct bt-fields-widget toplevel-frame parent-node-id fields
    (active-index 0))

  ;;; Create a `bt-fields-widget`.
  (define (make-fields-widget parent-node-id parent-path parent-widget)
    (let ((subnode-ids (md:config-get-subnode-type-ids parent-node-id
						       (current-config)
						       'field)))
      (if (null? subnode-ids)
	  #f
	  (let ((tl-frame (parent-widget 'create-widget 'frame
					 style: 'BT.TFrame)))
	    (make-bt-fields-widget
	     toplevel-frame: tl-frame
	     parent-node-id: parent-node-id
	     fields: (map (lambda (id)
			    (make-field-widget id tl-frame))
			  subnode-ids))))))

  ;;; Show a group fields widget.
  (define (show-fields-widget w group-instance-path)
    (begin
      (tk/pack (bt-fields-widget-toplevel-frame w)
	       fill: 'x)
      (for-each (lambda (field-widget)
		  (show-field-widget field-widget group-instance-path))
		(bt-fields-widget-fields w))))

  (define (focus-fields-widget w)
    (focus-field-widget (list-ref (bt-fields-widget-fields w)
				  (bt-fields-widget-active-index w))))

  (define (unfocus-fields-widget w)
    (unfocus-field-widget (list-ref (bt-fields-widget-fields w)
				    (bt-fields-widget-active-index w))))


  ;; ---------------------------------------------------------------------------
  ;;; ### The metatree widget
  ;; ---------------------------------------------------------------------------

  ;;; The `metatree` widget is a generic widget that implements a spreadsheet
  ;;; display. In Bintracker, it is used to display both MDAL blocks (patterns,
  ;;; tables, etc.) and the corresponding order or list view.
  ;;;
  ;;; Metatrees are implemented as a set of single-column `ttk::treeview`s on
  ;;; a canvas. The canvas takes care of horizontal scrolling, while the
  ;;; treeviews handle the vertical scrolling. Optionally, a row number column
  ;;; can be displayed, which is not part of the canvas (since it should not be
  ;;; scrolled horizontally).

  ;;; child record that wraps display related state such as the cursor position.
  (defstruct metatree-state
    cursor-x cursor-y)

  ;;; The main metatree structure.
  (defstruct metatree
    parent group-id type packframe rownums-packframe canvas
    block-ids column-ids columns rownums xscroll yscroll mtstate)

  ;;; Auxiliary procedure for `init-metatree`. Configure cell tags.
  (define (metatree-column-set-tags col)
    (col 'tag 'configure 'active-cell background: (colors 'cursor))
    (col 'tag 'configure 'rowhl-minor background: (colors 'row-highlight-minor))
    (col 'tag 'configure 'rowhl-major
	 background: (colors 'row-highlight-major))
    (col 'tag 'configure 'note foreground: (colors 'text-1))
    (col 'tag 'configure 'int foreground: (colors 'text-2))
    (col 'tag 'configure 'key foreground: (colors 'text-3))
    (col 'tag 'configure 'reference foreground: (colors 'text-4))
    (col 'tag 'configure 'trigger foreground: (colors 'text-5))
    (col 'tag 'configure 'string foreground: (colors 'text-6))
    (col 'tag 'configure 'modifier foreground: (colors 'text-7)))

  ;;; Get the appropriate command type tag to set the item color for metatrees.
  (define (get-command-type-tag field-id)
    (let ((command-config (md:config-get-inode-source-command
			   field-id (current-config))))
      (if (memq 'note (md:command-flags command-config))
	  'note
	  (match (md:command-type command-config)
	    ((or 'int 'uint) 'int)
	    ((or 'key 'ukey) 'key)
	    (else (md:command-type command-config))))))

  ;;; Deduces the "rowheight" setting of `ttk::treeview`. This assumes that
  ;;; the Treeview style has already been configured to use
  ;;; `(settings 'font-mono)` with `(settings 'font-size)`.
  ;;; This is necessary because Tk's `style lookup` command is broken, producing
  ;;; no result ca. 50% of the time.
  (define (get-treeview-rowheight)
    (+ 4 (string->number
	  (tk-eval (string-append "font metrics {-family \""
				  (settings 'font-mono) "\" -size "
				  (number->string (settings 'font-size))
				  "} -linespace")))))

  ;;; {{type}} - either 'block (show an igroup's blocks) or 'order (show iorder)
  (define (init-metatree parent type group-id)
    (let* ((packframe (parent 'create-widget 'frame))
	   (rownums-packframe (packframe 'create-widget 'frame))
	   (canvas (packframe 'create-widget 'canvas
			      scrollregion: "0 0 1000 1000"
			      bg: (colors 'background)
			      bd: 0 highlightthickness: 0))
	   (block-ids
	    (and (eq? type 'block)
		 (remove (lambda (id)
			   (eq? id (symbol-append group-id '_ORDER)))
			 (md:config-get-subnode-type-ids
			  group-id (current-config) 'block))))
	   (column-ids (if (eq? type 'block)
			   (flatten
			    (map (lambda (block-id)
				   (md:config-get-subnode-ids
				    block-id
				    (md:config-itree (current-config))))
				 block-ids))
			   (md:config-get-subnode-ids
			    (symbol-append group-id '_ORDER)
			    (md:config-itree (current-config)))))
	   (rownums (rownums-packframe 'create-widget 'treeview
				       selectmode: 'none
				       show: 'tree style: 'Metatree.Treeview))
	   (columns (map (lambda (id)
			   (let ((tree (canvas 'create-widget 'treeview
					       columns: 'content
					       selectmode: 'none show: '()
					       style: 'Metatree.Treeview)))
			     (tree 'column "#1" width: 80 anchor: 'center)
			     (metatree-column-set-tags tree)
			     tree))
			 column-ids)))
      (metatree-column-set-tags rownums)
      (make-metatree
       parent: parent group-id: group-id type: type packframe: packframe
       rownums-packframe: rownums-packframe
       canvas: canvas
       block-ids: block-ids column-ids: column-ids
       columns: columns rownums: rownums
       xscroll: (parent 'create-widget 'scrollbar orient: 'horizontal
			command: `(,canvas xview))
       yscroll: (packframe 'create-widget 'scrollbar orient: 'vertical
			   command:
			   (lambda args
			     (for-each (lambda (column)
					 (column 'yview 'moveto (cadr args)))
			   	       columns)
			     (rownums 'yview 'moveto (cadr args))))
       mtstate: (make-metatree-state cursor-x: 0 cursor-y: 0))))

  ;;; Pack the given metatree-widget. This only sets up the structure, but does
  ;;; not add any data. You most likely do not want to call this procedure
  ;;; directly, but rather invoke it through `update-order-view` or
  ;;; `update-blocks-view`.
  (define (show-metatree mt)
    (letrec* ((canvas (metatree-canvas mt))
	      (tree-rowheight (get-treeview-rowheight))
	      (header-font (list family: (settings 'font-mono)
				 size: (settings 'font-size)
				 weight: 'bold))
	      (pack-block-headers
	       (lambda (ids xpos)
		 (when (not (null? ids))
		   (let ((header-width
			  (* 80 (length (md:config-get-subnode-ids
					 (car ids)
					 (md:config-itree (current-config)))))))
		     (canvas 'create 'text
			     (list (+ xpos (quotient header-width 2))
				   0)
			     anchor: 'n width: header-width fill: (colors 'text)
			     font: header-font
			     text: (symbol->string (car ids)))
		     (pack-block-headers (cdr ids)
					 (+ xpos header-width))))))
	      (pack-columns
	       (lambda (columns column-ids xpos)
		 (when (not (null? columns))
		   (let ((init-ypos (if (eq? 'block (metatree-type mt))
					tree-rowheight 0)))
		     (canvas 'create 'text (list (+ xpos 40) init-ypos)
			     anchor: 'n width: 80 font: header-font
			     fill: (get-field-color (car column-ids))
			     text:
			     (let ((id (symbol->string (car column-ids))))
			       (if (eq? 'block (metatree-type mt))
				   id (string-drop id 2))))
		     (canvas 'create 'window
			     (list xpos (+ init-ypos tree-rowheight))
			     anchor: 'nw window: (car columns))
		     (tk/bind (car columns) '<Down> (lambda ()
						      (move-cursor mt 'down)))
		     (tk/bind (car columns) '<Up> (lambda ()
						    (move-cursor mt 'up)))
		     (tk/bind (car columns) '<Left> (lambda ()
						      (move-cursor mt 'left)))
		     (tk/bind (car columns) '<Right>
			      (lambda () (move-cursor mt 'right)))
		     ((car columns) 'configure height: 32)
		     (pack-columns (cdr columns)
				   (cdr column-ids)
				   (+ xpos 80)))))))
      (tk/pack (metatree-xscroll mt) expand: 0 fill: 'x side: 'bottom)
      (tk/pack (metatree-packframe mt) expand: 1 fill: 'both)
      ((metatree-rownums mt) 'column "#0" width: 80)
      (tk/pack (metatree-yscroll mt) fill: 'y side: 'right)
      (tk/pack (metatree-rownums-packframe mt) fill: 'y side: 'left)
      (tk/pack ((metatree-rownums-packframe mt) 'create-widget 'frame
		height: (if (eq? 'block (metatree-type mt))
			    (* 2 tree-rowheight)
			    tree-rowheight)
		style: 'BT.TFrame)
	       side: 'top fill: 'x)
      (tk/pack (metatree-rownums mt) fill: 'y expand: 1 side: 'top)
      (tk/pack canvas expand: 1 fill: 'both side: 'left)
      (when (eq? 'block (metatree-type mt))
	(pack-block-headers (metatree-block-ids mt) 0))
      (pack-columns (metatree-columns mt)
		    (metatree-column-ids mt)
		    0)
      (canvas 'configure xscrollcommand: (list (metatree-xscroll mt) 'set))
      (tk/bind
       (metatree-packframe mt) '<Configure>
       `(,(lambda (h)
      	    (for-each (lambda (column)
			(column 'configure height:
				(quotient
				 (- h (* tree-rowheight
					 (if (eq? 'block (metatree-type mt))
					     2 1)))
				 tree-rowheight)
				yscrollcommand: `(,(metatree-yscroll mt) set)))
      		      (metatree-columns mt)))
      	 %h))
      (canvas 'configure scrollregion:
	      (list 0 0 (* 80 (length (metatree-columns mt)))
		    1000))))

  ;;; Auxilliary procedure for `update-order-view`/`update-blocks-view`,
  ;;; displays {{len}} row numbers for the corresponding metatree display.
  ;;; Row numbers are padded by {{padding}} digits.
  ;;; Setting {{highlight}} to #t enables pattern-style row highlighting.
  (define (update-row-numbers metatree len padding highlight)
    (for-each (lambda (row)
		((metatree-rownums metatree) 'insert '{} 'end
		 text: (string-pad (number->string row
						   (app-settings-number-base
						    *bintracker-settings*))
				   padding #\0)
		 tags: (if highlight
			   (cond ((= 0 (modulo row 8)) "rowhl-major")
				 ((= 0 (modulo row 4)) "rowhl-minor")
				 (else ""))
			   "")))
	      (iota len)))

  ;;; Get the list of items in the given ttk::treeview. Items are returned as
  ;;; symbols.
  ;; TODO why return symbols?
  (define (tree-item-list tree)
    (map string->symbol (string-split (tree 'children '{}))))

  ;;; Get the item at {{index}} in the given ttk::treeview.
  (define (nth-tree-item tree index)
    (list-ref (tree-item-list tree) index))

  ;;; Get the number of items in the ttk::treeview.
  (define (tree-length tree)
    (length (tree-item-list tree)))

  ;;; Get the number of rows currently displayed by the given metatree.
  (define (metatree-length mt)
    (length (tree-item-list (car (metatree-columns mt)))))

  ;;; Apply {{method}} to the cursor of the given metatree {{mt}}. {{method}}
  ;;; shall be one of `'add` or `'remove`, which deletes resp. displays the
  ;;; cursor.
  (define (cursor-do mt method)
    (for-each (lambda (tree index)
		(when (= index (metatree-state-cursor-x (metatree-mtstate mt)))
		  (tree 'tag method "cursor-x" (tree-item-list tree))
		  (tree 'tag method "active-cell"
			(nth-tree-item tree (metatree-state-cursor-y
					     (metatree-mtstate mt)))))
		(tree 'tag method "cursor-y"
		      (nth-tree-item tree (metatree-state-cursor-y
					   (metatree-mtstate mt)))))
	      (metatree-columns mt)
	      (iota (length (metatree-column-ids mt))))
    ((metatree-rownums mt) 'tag method "cursor-y"
     (nth-tree-item (metatree-rownums mt)
		    (metatree-state-cursor-y (metatree-mtstate mt)))))

  ;;; Display the cursor of a metatree widget.
  (define (show-cursor mt)
    (cursor-do mt 'add))

  ;;; Remove the cursor of a metatree widget.
  (define (delete-cursor mt)
    (cursor-do mt 'remove))

  ;;; Move the cursor of the metatree {{mt}} in {{direction}}, which must be one
  ;;; of `'up`, `'down`, `'left`, `'right`
  ;; TODO this should consider the current edit step
  (define (move-cursor mt direction)
    (let ((current-xpos (metatree-state-cursor-x (metatree-mtstate mt)))
	  (current-ypos (metatree-state-cursor-y (metatree-mtstate mt))))
      (delete-cursor mt)
      (match direction
	('up (metatree-state-cursor-y-set!
	      (metatree-mtstate mt)
	      (sub1 (if (= current-ypos 0)
			(metatree-length mt)
			current-ypos))))
	('down (metatree-state-cursor-y-set!
		(metatree-mtstate mt)
		(let ((edit-step (if (= 0 (state 'edit-step))
				     1 (state 'edit-step))))
		  (if (>= (+ current-ypos edit-step)
			  (metatree-length mt))
		      0 (+ current-ypos edit-step)))))
	('left (metatree-state-cursor-x-set!
		(metatree-mtstate mt)
		(sub1 (if (= current-xpos 0)
			  (length (metatree-columns mt))
			  current-xpos))))
	('right (metatree-state-cursor-x-set!
		 (metatree-mtstate mt)
		 (if (>= (+ 1 current-xpos) (length (metatree-columns mt)))
		     0
		     (add1 current-xpos)))))
      (show-cursor mt)
      (when (and (eq? 'block (metatree-type mt))
		 (memq direction '(left right)))
	(update-active-block-column-info mt))))

  ;;;
  (define (focus-metatree mt)
    (show-cursor mt)
    (tk/focus (list-ref (metatree-columns mt)
			(metatree-state-cursor-x (metatree-mtstate mt))))
    (when (eq? 'block (metatree-type mt))
      (update-active-block-column-info mt)))

  ;;;
  (define (unfocus-metatree mt)
    (delete-cursor mt)
    (set-state! 'active-md-command-info "")
    (reset-status-text!))


  ;; ---------------------------------------------------------------------------
  ;;; ### Block Related Widgets and Procedures
  ;; ---------------------------------------------------------------------------

  (define (update-active-block-column-info metatree)
    (set-active-md-command-info!
     (list-ref (metatree-column-ids metatree)
	       (metatree-state-cursor-x (metatree-mtstate metatree))))
    (reset-status-text!))

  ;;; Update a group's order/block list view.
  (define (update-order-view metatree parent-node-instance-path)
    (letrec ((fill-empty-values
	      (lambda (vals previous)
		(if (null? vals)
		    '()
		    (let ((next-val (if (null? (car vals))
					previous (car vals))))
		      (cons next-val (fill-empty-values (cdr vals)
							next-val))))))
	     (block-values (md:mod-get-block-instance-values
	  		    ((md:node-instance-path
	  		      (string-append parent-node-instance-path "/"
	  				     (symbol->string
	  				      (metatree-group-id metatree))
	  				     "_ORDER/0"))
	  		     (md:mod-global-node (current-mod))))))
      (for-each (lambda (column values field-id)
		  (for-each (lambda (value)
			      (column 'insert '{} 'end tags: '(reference)
				      values:
				      (list (normalize-field-value value
								   field-id))))
			    values))
		(metatree-columns metatree)
		(map (lambda (fields) (fill-empty-values fields '()))
		     block-values)
		(md:config-get-subnode-ids
		 (symbol-append (metatree-group-id metatree)
				'_ORDER)
		 (md:config-itree (current-config))))
      (update-row-numbers metatree (length (car block-values))
			  3 #f)))

  ;;; Update a group's blocks view, based on the current position in the
  ;;; order or block list.
  (define (update-blocks-view metatree parent-node-instance-path order-pos)
    (let* ((parent-group-instance
	    ((md:node-instance-path parent-node-instance-path)
	     (md:mod-global-node (current-mod))))
	   (block-instance-ids
	    (list-ref (md:mod-get-order-values (metatree-group-id metatree)
					       parent-group-instance
					       (current-config))
		      order-pos))
	   (block-values
	    (concatenate
	     (map (lambda (block-id instance-id)
		    (md:mod-get-block-instance-values
		     ((md:node-instance-path
		       (string-append parent-node-instance-path "/"
				      (symbol->string block-id) "/"
				      (number->string instance-id)))
		      (md:mod-global-node (current-mod)))))
		  (metatree-block-ids metatree)
		  block-instance-ids))))
      (for-each
       (lambda (column values field-id)
	 (for-each (lambda (value rownum)
		     (column 'insert '{} 'end
			     values: (list
				      (normalize-field-value value field-id))
			     tags:
			     (list (get-command-type-tag field-id)
				   (cond ((= 0 (modulo rownum 8)) 'rowhl-major)
					 ((= 0 (modulo rownum 4)) 'rowhl-minor)
					 (else 'default)))))
		   values (iota (length values))))
       (metatree-columns metatree)
       block-values (metatree-column-ids metatree))
      (update-row-numbers metatree (length (car block-values))
			  ;; 4 digits for row numbers
			  4 #t)))

  ;;; Display the blocks of a group instance.
  ;;; TODO this must read the order position, or the list of instances must be
  ;;; passed in.
  (define (show-blocks-view metatree group-instance-path)
    (show-metatree metatree)
    (update-blocks-view metatree group-instance-path 0))

  ;;; Display the order or block list of a group instance.
  (define (show-order-view metatree group-instance-path)
    (show-metatree metatree)
    (update-order-view metatree group-instance-path))

  ;;; A metawidget for displaying a group's block members and the corresponding
  ;;; order or block list.
  ;;; TODO MDAL defines order/block lists as optional if blocks are
  ;;; single instance.
  (defstruct bt-blocks-widget
    tl-panedwindow blocks-pane order-pane blocks-view order-view)

  ;;; Create a `bt-blocks-widget`.
  (define (make-blocks-widget parent-node-id parent-path parent-widget)
    (let ((block-ids (md:config-get-subnode-type-ids parent-node-id
						     (current-config)
						     'block)))
      (if (null? block-ids)
	  #f
	  (let* ((.tl (parent-widget 'create-widget 'panedwindow
				     orient: 'horizontal))
		 (.blocks-pane (.tl 'create-widget 'frame))
		 (.order-pane (.tl 'create-widget 'frame)))
	    (make-bt-blocks-widget
	     tl-panedwindow: .tl
	     blocks-pane: .blocks-pane
	     order-pane: .order-pane
	     blocks-view: (init-metatree .blocks-pane 'block parent-node-id)
	     order-view: (init-metatree .order-pane 'order parent-node-id))))))

  ;;; Display a `bt-blocks-widget`.
  (define (show-blocks-widget w)
    (let ((top (bt-blocks-widget-tl-panedwindow w)))
      (begin
	(top 'add (bt-blocks-widget-blocks-pane w) weight: 2)
	(top 'add (bt-blocks-widget-order-pane w) weight: 1)
	(tk/pack top expand: 1 fill: 'both)
	(show-blocks-view (bt-blocks-widget-blocks-view w)
			  "0/PATTERNS/0")
	(show-order-view (bt-blocks-widget-order-view w)
			 "0/PATTERNS/0"))))

  ;;; The "main view" metawidget, displaying all subgroups of the GLOBAL node in
  ;;; a notebook (tabs) tk widget. It can be indirectly nested through a
  ;;; bt-group-widget, which is useful for subgroups that have subgroups
  ;;; themselves.
  ;;; bt-subgroups-widgets should be created through `make-subgroups-widget`.
  (defstruct bt-subgroups-widget
    toplevel-frame subgroup-ids tl-notebook notebook-frames subgroups)

  ;;; Create a `bt-subgroups-widget` as child of the given *parent-widget*.
  (define (make-subgroups-widget parent-node-id parent-path parent-widget)
    (let ((sg-ids (md:config-get-subnode-type-ids parent-node-id
						  (current-config)
						  'group)))
      (if (null? sg-ids)
	  #f
	  (let* ((tl-frame (parent-widget 'create-widget 'frame))
		 (notebook (tl-frame 'create-widget 'notebook
				     style: 'BT.TNotebook))
		 (subgroup-frames (map (lambda (id)
					 (notebook 'create-widget 'frame))
				       sg-ids)))
	    (make-bt-subgroups-widget
	     toplevel-frame: tl-frame
	     subgroup-ids: sg-ids
	     tl-notebook: notebook
	     notebook-frames: subgroup-frames
	     subgroups: (map (lambda (id frame)
			       (make-group-widget
				id (string-append parent-path
						  (symbol->string id) "/0/")
				frame))
			     sg-ids subgroup-frames))))))

  ;;; Pack a bt-subgroups-widget to the display.
  (define (show-subgroups-widget w)
    (tk/pack (bt-subgroups-widget-toplevel-frame w)
	     expand: 1 fill: 'both)
    (tk/pack (bt-subgroups-widget-tl-notebook w)
	     expand: 1 fill: 'both)
    (for-each (lambda (sg-id sg-frame)
		((bt-subgroups-widget-tl-notebook w)
		 'add sg-frame text: (symbol->string sg-id)))
	      (bt-subgroups-widget-subgroup-ids w)
	      (bt-subgroups-widget-notebook-frames w))
    (for-each (lambda (subgroup-widget)
		(show-group-widget subgroup-widget ""))
	      (bt-subgroups-widget-subgroups w)))

  ;; Not exported.
  (defstruct bt-group-widget
    toplevel-frame fields-widget blocks-widget subgroups-widget)

  ;; TODO handle groups with multiple instances
  ;; parent-path is misleading, it should be the igroup path itself
  (define (make-group-widget node-id parent-path parent-widget)
    (let ((tl-frame (parent-widget 'create-widget 'frame))
	  (instance-path (string-append parent-path "0/")))
      (make-bt-group-widget
       toplevel-frame: tl-frame
       fields-widget: (make-fields-widget node-id instance-path tl-frame)
       blocks-widget: (make-blocks-widget node-id instance-path tl-frame)
       subgroups-widget: (make-subgroups-widget node-id instance-path
						tl-frame))))

  ;; Display the group widget (using pack geometry manager).
  (define (show-group-widget w group-instance-path)
    (begin
      (tk/pack (bt-group-widget-toplevel-frame w)
	       expand: 1 fill: 'both)
      (when (bt-group-widget-fields-widget w)
	(show-fields-widget (bt-group-widget-fields-widget w)
			    group-instance-path))
      (when (bt-group-widget-blocks-widget w)
	(show-blocks-widget (bt-group-widget-blocks-widget w)))
      (when (bt-group-widget-subgroups-widget w)
	(show-subgroups-widget (bt-group-widget-subgroups-widget w)))
      (when (not (or (bt-group-widget-blocks-widget w)
		     (bt-group-widget-subgroups-widget w)))
	(tk/pack ((bt-group-widget-toplevel-frame w)
		  'create-widget 'frame)
		 expand: 1 fill: 'both))))

  (define (destroy-group-widget w)
    (tk/destroy (bt-group-widget-toplevel-frame w)))

  (define (make-module-widget parent)
    (make-group-widget 'GLOBAL "" parent))

  (define (show-module)
    (show-group-widget (state 'module-widget)
		       "0/"))

  ;; ---------------------------------------------------------------------------
  ;;; ## Accessors
  ;; ---------------------------------------------------------------------------

  (define (current-fields-view)
    (bt-group-widget-fields-widget (state 'module-widget)))

  ;;; Returns the currently visible blocks metatree
  ;; TODO assumes first subgroup is shown, check actual state
  (define (current-blocks-view)
    (bt-blocks-widget-blocks-view
     (bt-group-widget-blocks-widget
      (car (bt-subgroups-widget-subgroups
	    (bt-group-widget-subgroups-widget (state 'module-widget)))))))

  ;;; Returns the currently visible order metatree
  ;; TODO assumes first subgroup is shown, check actual state
  (define (current-order-view)
    (bt-blocks-widget-order-view
     (bt-group-widget-blocks-widget
      (car (bt-subgroups-widget-subgroups
	    (bt-group-widget-subgroups-widget (state 'module-widget)))))))


  ;; ---------------------------------------------------------------------------
  ;;; ## Utilities
  ;; ---------------------------------------------------------------------------

  ;;; Disable automatic keyboard traversal. Needed because it messes with key
  ;;; binding involving Tab.
  (define (disable-keyboard-traversal)
    (tk/event 'delete '<<NextWindow>>)
    (tk/event 'delete '<<PrevWindow>>))

    ;;; update window title by looking at current file name and 'modified'
  ;;; property
  (define (update-window-title!)
    (tk/wm 'title tk (if (state 'current-file)
			 (string-append (pathname-file (state 'current-file))
					(if (state 'modified)
					    "*" "")
					" - Bintracker")
			 "Bintracker")))

  ) ;; end module bt-gui
