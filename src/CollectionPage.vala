/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

class SlideshowPage : SinglePhotoPage {
    private const int CHECK_ADVANCE_MSEC = 250;
    
    private ViewCollection controller;
    private Thumbnail current;
    private Gdk.Pixbuf next_pixbuf = null;
    private Thumbnail next_thumbnail = null;
    private Gtk.Toolbar toolbar = new Gtk.Toolbar();
    private Gtk.ToolButton play_pause_button;
    private Gtk.ToolButton settings_button;
    private Timer timer = new Timer();
    private bool playing = true;
    private bool exiting = false;

    public signal void hide_toolbar();
    
    private class SettingsDialog : Gtk.Dialog {
        Gtk.Entry delay_entry;
        double delay;
        Gtk.HScale hscale;

        private bool update_entry(Gtk.ScrollType scroll, double new_value) {
            new_value = new_value.clamp(Config.SLIDESHOW_DELAY_MIN, Config.SLIDESHOW_DELAY_MAX);

            delay_entry.set_text("%.1f".printf(new_value));
            return false;
        }

        private void check_text() { //rename this function
            // parse through text, set delay
            string delay_text = delay_entry.get_text();
            delay_text.canon("0123456789.",'?');
            delay_text = delay_text.replace("?","");
         
            delay = delay_text.to_double();
            delay_entry.set_text(delay_text);

            delay = delay.clamp(Config.SLIDESHOW_DELAY_MIN, Config.SLIDESHOW_DELAY_MAX);
            hscale.set_value(delay);
        }        

        public SettingsDialog() {
            delay = Config.get_instance().get_slideshow_delay();

            set_modal(true);
            set_transient_for(AppWindow.get_fullscreen());

            add_buttons(Gtk.STOCK_CANCEL, Gtk.ResponseType.CANCEL, 
                        Gtk.STOCK_OK, Gtk.ResponseType.OK);
            set_title(_("Settings"));

            Gtk.Label delay_label = new Gtk.Label(_("Delay:"));
            Gtk.Label units_label = new Gtk.Label(_("seconds"));
            delay_entry = new Gtk.Entry();
            delay_entry.set_max_length(5);
            delay_entry.set_text("%.1f".printf(delay));
            delay_entry.set_width_chars(4);
            delay_entry.set_activates_default(true);
            delay_entry.changed += check_text;

            Gtk.Adjustment adjustment = new Gtk.Adjustment(delay, Config.SLIDESHOW_DELAY_MIN, Config.SLIDESHOW_DELAY_MAX + 1, 0.1, 1, 1);
            hscale = new Gtk.HScale(adjustment);
            hscale.set_draw_value(false);
            hscale.set_size_request(150,-1);
            hscale.change_value += update_entry;

            Gtk.HBox query = new Gtk.HBox(false, 0);
            query.pack_start(delay_label, false, false, 3);
            query.pack_start(hscale, true, true, 3);
            query.pack_start(delay_entry, false, false, 3);
            query.pack_start(units_label, false, false, 3);

            set_default_response(Gtk.ResponseType.OK);

            vbox.pack_start(query, true, false, 6);
        }

        public double get_delay() {
            return delay;
        }
    }

    public SlideshowPage(ViewCollection controller, Thumbnail start) {
        base(_("Slideshow"));
        
        this.controller = controller;
        current = start;
        
        set_default_interp(QUALITY_INTERP);
        
        // add toolbar buttons
        Gtk.ToolButton previous_button = new Gtk.ToolButton.from_stock(Gtk.STOCK_GO_BACK);
        previous_button.set_label(_("Back"));
        previous_button.set_tooltip_text(_("Go to the previous photo"));
        previous_button.clicked += on_previous_manual;
        
        toolbar.insert(previous_button, -1);
        
        play_pause_button = new Gtk.ToolButton.from_stock(Gtk.STOCK_MEDIA_PAUSE);
        play_pause_button.set_label(_("Pause"));
        play_pause_button.set_tooltip_text(_("Pause the slideshow"));
        play_pause_button.clicked += on_play_pause;
        
        toolbar.insert(play_pause_button, -1);
        
        Gtk.ToolButton next_button = new Gtk.ToolButton.from_stock(Gtk.STOCK_GO_FORWARD);
        next_button.set_label(_("Next"));
        next_button.set_tooltip_text(_("Go to the next photo"));
        next_button.clicked += on_next_manual;
        
        toolbar.insert(next_button, -1);

        settings_button = new Gtk.ToolButton.from_stock(Gtk.STOCK_PREFERENCES);
        settings_button.set_label(_("Settings"));
        settings_button.set_tooltip_text(_("Change slideshow settings"));
        settings_button.clicked += on_change_settings;
        
        toolbar.insert(settings_button, -1);
    }
    
    public override Gtk.Toolbar get_toolbar() {
        return toolbar;
    }
    
    public override void switched_to() {
        base.switched_to();

        Idle.add(start_slideshow);
    }

    private bool start_slideshow() {
        // since the canvas might not be ready at this point, start with screen-sized photo
        Gdk.Pixbuf pixbuf;
        if (!get_fullscreen_pixbuf(current, true, out current, out pixbuf))
            return false;

        set_pixbuf(pixbuf);
        
        // start the auto-advance timer
        Timeout.add(CHECK_ADVANCE_MSEC, auto_advance);
        timer.start();
        
        // prefetch the next pixbuf so it's ready when auto-advance fires
        schedule_prefetch();

        return false;
    }
    
    public override void switching_from() {
        base.switching_from();

        exiting = true;
    }
    
    private void schedule_prefetch() {
        next_pixbuf = null;
        Idle.add(prefetch_next_pixbuf);
    }

    private bool get_fullscreen_pixbuf(Thumbnail start, bool forward, out Thumbnail next, out Gdk.Pixbuf next_pixbuf) {
        next = start;

        for (;;) {
            try {
                // Fails if a photo source file is missing.
                next_pixbuf = next.get_photo().get_pixbuf(Scaling.for_screen());
            } catch (Error err) {
                warning("%s", err.message);

                // Look for the next good photo.
                next = (Thumbnail) ((forward) ? controller.get_next(next) : controller.get_previous(next));

                // An entire slideshow set might be missing, so check for a loop.
                if ((next == start && next != current) || next == current) {
                    Gtk.MessageDialog dialog = new Gtk.MessageDialog(AppWindow.get_fullscreen(),
                        Gtk.DialogFlags.MODAL, Gtk.MessageType.ERROR, Gtk.ButtonsType.OK, "%s",
                        _("All photo source files are missing."));
                    dialog.title = Resources.APP_TITLE;
                    dialog.run();
                    dialog.destroy();

                    AppWindow.get_instance().end_fullscreen();

                    next = null;
                    next_pixbuf = null;

                    return false;
                }

                continue;
            }
            return true;
        }
    }

    private bool prefetch_next_pixbuf() {
        // if multiple prefetches get lined up in the queue, this stops them from doing multiple
        // pipelines
        if (next_pixbuf != null)
            return false;
        
        get_fullscreen_pixbuf((Thumbnail) controller.get_next(current), true, out next_thumbnail, out next_pixbuf);
        
        return false;
    }
    
    private void on_play_pause() {
        if (playing) {
            play_pause_button.set_stock_id(Gtk.STOCK_MEDIA_PLAY);
            play_pause_button.set_label(_("Play"));
            play_pause_button.set_tooltip_text(_("Continue the slideshow"));
        } else {
            play_pause_button.set_stock_id(Gtk.STOCK_MEDIA_PAUSE);
            play_pause_button.set_label(_("Pause"));
            play_pause_button.set_tooltip_text(_("Pause the slideshow"));
        }
        
        playing = !playing;
        
        // reset the timer
        timer.start();
    }
    
    private void on_previous_manual() {
        manual_advance((Thumbnail) controller.get_previous(current), false);
    }
    
    private void on_next_automatic() {
        current = ((current == next_thumbnail) ? (Thumbnail) controller.get_next(current) : next_thumbnail);
        
        // if prefetch didn't happen in time, get pixbuf now
        Gdk.Pixbuf pixbuf = next_pixbuf;
        if (pixbuf == null) {
            warning("Slideshow prefetch was not ready");

            get_fullscreen_pixbuf(current, true, out current, out pixbuf);
        }
        
        if (pixbuf != null)
            set_pixbuf(pixbuf);
        
        // reset the timer
        timer.start();
        
        // prefetch the next pixbuf
        schedule_prefetch();
    }
    
    private void on_next_manual() {
        manual_advance((Thumbnail) controller.get_next(current), true);
    }
    
    private void manual_advance(Thumbnail thumbnail, bool forward) {
        current = thumbnail;
        
        // set pixbuf
        Gdk.Pixbuf next_pixbuf;
        get_fullscreen_pixbuf(current, forward, out current, out next_pixbuf);
        set_pixbuf(next_pixbuf);
        
        // reset the advance timer
        timer.start();
        
        // prefetch the next pixbuf
        schedule_prefetch();
    }

    private bool auto_advance() {
        if (exiting)
            return false;
        
        if (!playing)
            return true;
        
        if (timer.elapsed() < Config.get_instance().get_slideshow_delay())
            return true;
        
        on_next_automatic();
        
        return true;
    }
    
    private override bool key_press_event(Gdk.EventKey event) {
        bool handled = true;
        switch (Gdk.keyval_name(event.keyval)) {
            case "space":
                on_play_pause();
            break;
            
            case "Left":
            case "KP_Left":
                on_previous_manual();
            break;
            
            case "Right":
            case "KP_Right":
                on_next_manual();
            break;
            
            default:
                handled = false;
            break;
        }
        
        if (handled)
            return true;
        
        return (base.key_press_event != null) ? base.key_press_event(event) : true;
    }

    private void on_change_settings() {
        SettingsDialog settings_dialog = new SettingsDialog();
        settings_dialog.show_all();
        bool slideshow_playing = playing;
        playing = false;
        hide_toolbar();

        int response = settings_dialog.run();
        if (response == Gtk.ResponseType.OK) {
            // sync with the config setting so it will persist
            Config.get_instance().set_slideshow_delay(settings_dialog.get_delay());
        }

        settings_dialog.destroy();
        playing = slideshow_playing;
        timer.start();
    }
}

public class CollectionViewManager : ViewManager {
    private CollectionPage page;
    
    public CollectionViewManager(CollectionPage page) {
        this.page = page;
    }
    
    public override DataView create_view(DataSource source) {
        return page.create_thumbnail((LibraryPhoto) source);
    }
}

public class CollectionPage : CheckerboardPage {
    public const int SORT_BY_MIN = 0;
    public const int SORT_BY_NAME = 0;
    public const int SORT_BY_EXPOSURE_DATE = 1;
    public const int SORT_BY_MAX = 1;
    
    public const int SORT_ORDER_MIN = 0;
    public const int SORT_ORDER_ASCENDING = 0;
    public const int SORT_ORDER_DESCENDING = 1;
    public const int SORT_ORDER_MAX = 1;
    
    public const int DEFAULT_SORT_BY = SORT_BY_EXPOSURE_DATE;
    public const int DEFAULT_SORT_ORDER = SORT_ORDER_DESCENDING;

    // steppings should divide evenly into (Thumbnail.MAX_SCALE - Thumbnail.MIN_SCALE)
    public const int MANUAL_STEPPING = 16;
    public const int SLIDER_STEPPING = 2;

    private const int IMPROVAL_PRIORITY = Priority.LOW;
    private const int IMPROVAL_DELAY_MS = 250;

    private int drag_failed_item_count = 0;
    
    private class CompareName : Comparator<LayoutItem> {
        private bool ascending;
        
        public CompareName(bool ascending) {
            this.ascending = ascending;
        }
        
        public override int64 compare(LayoutItem a, LayoutItem b) {
            string namea = ((Thumbnail) a).get_title();
            string nameb = ((Thumbnail) b).get_title();
            
            return (ascending) ? strcmp(namea, nameb) : strcmp(nameb, namea);
        }
    }
    
    private class CompareDate : Comparator<LayoutItem> {
        private bool ascending;
        
        public CompareDate(bool ascending) {
            this.ascending = ascending;
        }
        
        public override int64 compare(LayoutItem a, LayoutItem b) {
            time_t timea = ((Thumbnail) a).get_photo().get_exposure_time();
            time_t timeb = ((Thumbnail) b).get_photo().get_exposure_time();
            
            return (ascending) ? timea - timeb : timeb - timea;
        }
    }
    
    private static Gtk.Adjustment slider_adjustment = null;
    
    private Gtk.Toolbar toolbar = new Gtk.Toolbar();
    private Gtk.HScale slider = null;
    private Gtk.ToolButton rotate_button = null;
    private Gtk.ToolButton slideshow_button = null;
    private int scale = Thumbnail.DEFAULT_SCALE;
    private bool improval_scheduled = false;
    private bool reschedule_improval = false;
    private Gee.ArrayList<File> drag_items = new Gee.ArrayList<File>();
    private bool thumbs_resized = false;

    public CollectionPage(string page_name, string? ui_filename = null, 
        Gtk.ActionEntry[]? child_actions = null) {
        base(page_name);
        
        init_ui_start("collection.ui", "CollectionActionGroup", create_actions(),
            create_toggle_actions());
        action_group.add_radio_actions(create_sort_crit_actions(), DEFAULT_SORT_BY,
            on_sort_changed);
        action_group.add_radio_actions(create_sort_order_actions(), DEFAULT_SORT_ORDER,
            on_sort_changed);

        if (ui_filename != null)
            init_load_ui(ui_filename);
        
        if (child_actions != null)
            action_group.add_actions(child_actions, this);
        
        init_ui_bind("/CollectionMenuBar");
        init_item_context_menu("/CollectionContextMenu");
        
        get_view().set_comparator(get_sort_comparator());
        get_view().contents_altered += on_contents_altered;
        get_view().items_state_changed += on_selection_changed;
        get_view().item_view_altered += on_thumbnail_view_altered;

        // adjustment which is shared by all sliders in the application
        if (slider_adjustment == null)
            slider_adjustment = new Gtk.Adjustment(scale_to_slider(scale), 0, 
                scale_to_slider(Thumbnail.MAX_SCALE), 1, 10, 0);
        
        // set up page's toolbar (used by AppWindow for layout)
        //
        // rotate tool
        rotate_button = new Gtk.ToolButton.from_stock(Resources.CLOCKWISE);
        rotate_button.set_label(Resources.ROTATE_CW_LABEL);
        rotate_button.set_tooltip_text(Resources.ROTATE_CW_TOOLTIP);
        rotate_button.sensitive = false;
        rotate_button.clicked += on_rotate_clockwise;
        
        toolbar.insert(rotate_button, -1);
        
        // slideshow button
        slideshow_button = new Gtk.ToolButton.from_stock(Gtk.STOCK_MEDIA_PLAY);
        slideshow_button.set_label(_("Slideshow"));
        slideshow_button.set_tooltip_text(_("Start a slideshow of these photos"));
        slideshow_button.sensitive = false;
        slideshow_button.clicked += on_slideshow;
        
        toolbar.insert(slideshow_button, -1);
        
        // separator to force slider to right side of toolbar
        Gtk.SeparatorToolItem separator = new Gtk.SeparatorToolItem();
        separator.set_expand(true);
        separator.set_draw(false);
        
        toolbar.insert(separator, -1);
        
        // thumbnail size slider
        slider = new Gtk.HScale(slider_adjustment);
        slider.value_changed += on_slider_changed;
        slider.set_draw_value(false);

        Gtk.ToolItem toolitem = new Gtk.ToolItem();
        toolitem.add(slider);
        toolitem.set_expand(false);
        toolitem.set_size_request(200, -1);
        toolitem.set_tooltip_text(_("Adjust the size of the thumbnails"));
        
        toolbar.insert(toolitem, -1);
        
        // initialize scale from slider (since the scale adjustment may be modified from default)
        scale = slider_to_scale(slider.get_value());

        // scrollbar policy
        set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC);
        
        // this schedules thumbnail improvement whenever the window is scrolled (and new
        // thumbnails may be exposed)
        get_hadjustment().value_changed += schedule_thumbnail_improval;
        get_vadjustment().value_changed += schedule_thumbnail_improval;
        
        show_all();

        schedule_thumbnail_improval();

        enable_drag_source(Gdk.DragAction.COPY);
    }
    
    private Gtk.ActionEntry[] create_actions() {
        Gtk.ActionEntry[] actions = new Gtk.ActionEntry[0];
        
        Gtk.ActionEntry file = { "FileMenu", null, TRANSLATABLE, null, null, on_file_menu };
        file.label = _("_File");
        actions += file;

        Gtk.ActionEntry export = { "Export", Gtk.STOCK_SAVE_AS, TRANSLATABLE, "<Ctrl>E",
            TRANSLATABLE, on_export };
        export.label = _("_Export Photos...");
        export.tooltip = _("Export selected photos to disk");
        actions += export;

        Gtk.ActionEntry edit = { "EditMenu", null, TRANSLATABLE, null, null, on_edit_menu };
        edit.label = _("_Edit");
        actions += edit;

        Gtk.ActionEntry select_all = { "SelectAll", Gtk.STOCK_SELECT_ALL, TRANSLATABLE,
            "<Ctrl>A", TRANSLATABLE, on_select_all };
        select_all.label = _("Select _All");
        select_all.tooltip = _("Select all the photos in the library");
        actions += select_all;

        Gtk.ActionEntry remove = { "Remove", Gtk.STOCK_DELETE, TRANSLATABLE, "Delete",
            TRANSLATABLE, on_remove };
        remove.label = _("_Remove");
        remove.tooltip = _("Remove the selected photos from the library");
        actions += remove;

        Gtk.ActionEntry photos = { "PhotosMenu", null, TRANSLATABLE, null, null,
            on_photos_menu };
        photos.label = _("_Photos");
        actions += photos;

        Gtk.ActionEntry increase_size = { "IncreaseSize", Gtk.STOCK_ZOOM_IN, TRANSLATABLE,
            "bracketright", TRANSLATABLE, on_increase_size };
        increase_size.label = _("Zoom _In");
        increase_size.tooltip = _("Increase the magnification of the thumbnails");
        actions += increase_size;

        Gtk.ActionEntry decrease_size = { "DecreaseSize", Gtk.STOCK_ZOOM_OUT, TRANSLATABLE,
            "bracketleft", TRANSLATABLE, on_decrease_size };
        decrease_size.label = _("Zoom _Out");
        decrease_size.tooltip = _("Decrease the magnification of the thumbnails");
        actions += decrease_size;

        Gtk.ActionEntry rotate_right = { "RotateClockwise", Resources.CLOCKWISE,
            TRANSLATABLE, "<Ctrl>R", TRANSLATABLE, on_rotate_clockwise };
        rotate_right.label = _("Rotate _Right");
        rotate_right.tooltip = _("Rotate the selected photos clockwise");
        actions += rotate_right;

        Gtk.ActionEntry rotate_left = { "RotateCounterclockwise", Resources.COUNTERCLOCKWISE,
            TRANSLATABLE, "<Ctrl><Shift>R", TRANSLATABLE, on_rotate_counterclockwise };
        rotate_left.label = _("Rotate _Left");
        rotate_left.tooltip = _("Rotate the selected photos counterclockwise");
        actions += rotate_left;

        Gtk.ActionEntry mirror = { "Mirror", Resources.MIRROR, TRANSLATABLE, "<Ctrl>M",
            TRANSLATABLE, on_mirror };
        mirror.label = _("_Mirror");
        mirror.tooltip = _("Make mirror images of the selected photos");
        actions += mirror;

        Gtk.ActionEntry revert = { "Revert", Gtk.STOCK_REVERT_TO_SAVED, TRANSLATABLE, null,
            TRANSLATABLE, on_revert };
        revert.label = _("Re_vert to Original");
        revert.tooltip = _("Revert to original photo");
        actions += revert;

        Gtk.ActionEntry slideshow = { "Slideshow", Gtk.STOCK_MEDIA_PLAY, TRANSLATABLE, "F5",
            TRANSLATABLE, on_slideshow };
        slideshow.label = _("_Slideshow");
        slideshow.tooltip = _("Play a slideshow");
        actions += slideshow;

        Gtk.ActionEntry view = { "ViewMenu", null, TRANSLATABLE, null, null, on_view_menu };
        view.label = _("_View");
        actions += view;

        Gtk.ActionEntry sort_photos = { "SortPhotos", null, TRANSLATABLE, null, null, null };
        sort_photos.label = _("Sort _Photos");
        actions += sort_photos;

        Gtk.ActionEntry help = { "HelpMenu", null, TRANSLATABLE, null, null, null };
        help.label = _("_Help");
        actions += help;
        
        return actions;
    }
    
    private Gtk.ToggleActionEntry[] create_toggle_actions() {
        Gtk.ToggleActionEntry[] toggle_actions = new Gtk.ToggleActionEntry[0];

        Gtk.ToggleActionEntry titles = { "ViewTitle", null, TRANSLATABLE, "<Ctrl><Shift>T",
            TRANSLATABLE, on_display_titles, true };
        titles.label = _("_Titles");
        titles.tooltip = _("Display the title of each photo");
        toggle_actions += titles;

        return toggle_actions;
    }
    
    private Gtk.RadioActionEntry[] create_sort_crit_actions() {
        Gtk.RadioActionEntry[] sort_crit_actions = new Gtk.RadioActionEntry[0];

        Gtk.RadioActionEntry by_name = { "SortByName", null, TRANSLATABLE, null, TRANSLATABLE,
            SORT_BY_NAME };
        by_name.label = _("By _Name");
        by_name.tooltip = _("Sort photos by name");
        sort_crit_actions += by_name;

        Gtk.RadioActionEntry by_date = { "SortByExposureDate", null, TRANSLATABLE, null,
            TRANSLATABLE, SORT_BY_EXPOSURE_DATE };
        by_date.label = _("By Exposure _Date");
        by_date.tooltip = _("Sort photos by exposure date");
        sort_crit_actions += by_date;

        return sort_crit_actions;
    }
    
    private Gtk.RadioActionEntry[] create_sort_order_actions() {
        Gtk.RadioActionEntry[] sort_order_actions = new Gtk.RadioActionEntry[0];

        Gtk.RadioActionEntry ascending = { "SortAscending", Gtk.STOCK_SORT_ASCENDING,
            TRANSLATABLE, null, TRANSLATABLE, SORT_ORDER_ASCENDING };
        ascending.label = _("_Ascending");
        ascending.tooltip = _("Sort photos in an ascending order");
        sort_order_actions += ascending;

        Gtk.RadioActionEntry descending = { "SortDescending", Gtk.STOCK_SORT_DESCENDING,
            TRANSLATABLE, null, TRANSLATABLE, SORT_ORDER_DESCENDING };
        descending.label = _("D_escending");
        descending.tooltip = _("Sort photos in a descending order");
        sort_order_actions += descending;

        return sort_order_actions;
    }

    public override Gtk.Toolbar get_toolbar() {
        return toolbar;
    }
    
    // This method is called by CollectionViewManager to create thumbnails for the DataSource 
    // (Photo) objects.
    public virtual Thumbnail create_thumbnail(LibraryPhoto photo) {
        Thumbnail thumbnail = new Thumbnail(photo, scale);
        thumbnail.display_title(display_titles());
        
        return thumbnail;
    }
    
    public override void switched_to() {
        base.switched_to();

        // if the thumbnails were resized while viewing another page, resize the ones on this page
        // now ... set_thumb_size does the refresh and thumbnail improval, so don't schedule if
        // going this route
        if (thumbs_resized) {
            set_thumb_size(slider_to_scale(slider.get_value()));
            thumbs_resized = false;
        } else {
            // need to refresh the layout in case any of the thumbnail dimensions were altered while we
            // were gone
            refresh("switched_to");
            
            // schedule improvement in case any new photos were added
            schedule_thumbnail_improval();
        }
    }
    
    public override void returning_from_fullscreen() {
        refresh("returning_from_fullscreen");
        
        base.returning_from_fullscreen();
    }
    
    private void on_contents_altered() {
        slideshow_button.sensitive = get_view().get_count() > 0;
    }
    
    private void on_selection_changed(Gee.Iterable<DataView> items) {
        rotate_button.sensitive = get_view().get_selected_count() > 0;
    }
    
    protected override void on_item_activated(LayoutItem item) {
        Thumbnail thumbnail = (Thumbnail) item;
        
        // switch to full-page view
        debug("switching to %s", thumbnail.get_photo().to_string());

        LibraryWindow.get_app().switch_to_photo_page(this, thumbnail);
    }
    
    protected override bool on_context_invoked(Gtk.Menu context_menu) {
        bool selected = get_view().get_selected_count() > 0;
        bool revert_possible = can_revert_selected();
        
        set_item_sensitive("/CollectionContextMenu/ContextRemove", selected);
        set_item_sensitive("/CollectionContextMenu/ContextRotateClockwise", selected);
        set_item_sensitive("/CollectionContextMenu/ContextRotateCounterclockwise", selected);
        set_item_sensitive("/CollectionContextMenu/ContextMirror", selected);
        set_item_sensitive("/CollectionContextMenu/ContextRevert", selected && revert_possible);

        return true;
    }
    
    public override LayoutItem? get_fullscreen_photo() {
        // use first selected item; if no selection, use first item
        if (get_view().get_selected_count() > 0)
            return (LayoutItem?) get_view().get_selected_at(0);
        else if (get_view().get_count() > 0)
            return (LayoutItem?) get_view().get_at(0);
        else
            return null;
    }
    
    protected override void on_resize(Gdk.Rectangle rect) {
        // this schedules thumbnail improvement whenever the window size changes (and new thumbnails
        // may be exposed), therefore, uninterested in window position move
        schedule_thumbnail_improval();
    }
    
    private override void drag_begin(Gdk.DragContext context) {
        if (get_view().get_selected_count() == 0)
            return;
        
        drag_items.clear();

        // because drag_data_get may be called multiple times in a single drag, prepare all the exported
        // files first
        Gdk.Pixbuf icon = null;
        drag_failed_item_count = 0;
        foreach (DataView view in get_view().get_selected()) {
            LibraryPhoto photo = ((Thumbnail) view).get_photo();
            
            File file = null;
            try {
                file = photo.generate_exportable();
                drag_items.add(file);
            } catch (Error err) {
                drag_failed_item_count++;
                warning("%s", err.message);
            }
            
            try {
                // set up icon using the "first" photo, although Sets are not ordered
                if (icon == null) {
                    icon = photo.get_preview_pixbuf(Scaling.for_best_fit(
                        AppWindow.DND_ICON_SCALE));
                }
            } catch (Error err) {
                warning("%s", err.message);
            }

            if (file != null)
                debug("Prepared %s for export", file.get_path());
        }
        
        if (icon != null)
            Gtk.drag_source_set_icon_pixbuf(get_event_source(), icon);
    }
    
    private override void drag_data_get(Gdk.DragContext context, Gtk.SelectionData selection_data,
        uint target_type, uint time) {
        assert(target_type == TargetType.URI_LIST);
        
        if (drag_items.size == 0)
            return;
        
        // prepare list of uris
        string[] uris = new string[drag_items.size];
        int ctr = 0;
        foreach (File file in drag_items)
            uris[ctr++] = file.get_uri();
        
        selection_data.set_uris(uris);
    }
    
    private override void drag_end(Gdk.DragContext context) {
        drag_items.clear();

        if (drag_failed_item_count > 0) {
            Idle.add(report_drag_failed);
        }
    }

    private bool report_drag_failed() {
        AppWindow.error_message(drag_failed_item_count == 1 ? _("A photo source file is missing.") : 
            _("%d photo source files missing.").printf(drag_failed_item_count));
        drag_failed_item_count = 0;

        return false;
    }
    
    private override bool source_drag_failed(Gdk.DragContext context, Gtk.DragResult drag_result) {
        debug("Drag failed: %d", (int) drag_result);
        
        drag_items.clear();
        
        foreach (DataView view in get_view().get_selected())
            ((Thumbnail) view).get_photo().export_failed();
        
        return false;
    }
    
    public int increase_thumb_size() {
        if (scale == Thumbnail.MAX_SCALE)
            return scale;
        
        scale += MANUAL_STEPPING;
        if (scale > Thumbnail.MAX_SCALE)
            scale = Thumbnail.MAX_SCALE;
        
        set_thumb_size(scale);
        
        return scale;
    }
    
    public int decrease_thumb_size() {
        if (scale == Thumbnail.MIN_SCALE)
            return scale;
        
        scale -= MANUAL_STEPPING;
        if (scale < Thumbnail.MIN_SCALE)
            scale = Thumbnail.MIN_SCALE;
        
        set_thumb_size(scale);

        return scale;
    }
    
    public void set_thumb_size(int new_scale) {
        assert(new_scale >= Thumbnail.MIN_SCALE);
        assert(new_scale <= Thumbnail.MAX_SCALE);
        
        scale = new_scale;
        
        foreach (DataObject object in get_view().get_all())
            ((Thumbnail) object).resize(scale);
    }
    
    private void on_thumbnail_view_altered(DataView view) {
        // ignore if not in view
        if (!is_in_view())
            return;
            
        Thumbnail thumbnail = (Thumbnail) view;
        
        // no worries if not exposed
        if (!thumbnail.is_exposed())
            return;
        
        // if low-quality thumbnail, schedule for improval
        if (thumbnail.is_low_quality_thumbnail())
            schedule_thumbnail_improval();
    }
    
    private void schedule_thumbnail_improval() {
        // don't bother if not in view
        if (!is_in_view())
            return;
            
        if (improval_scheduled == false) {
            improval_scheduled = true;
            Timeout.add_full(IMPROVAL_PRIORITY, IMPROVAL_DELAY_MS, background_improval);
        } else {
            reschedule_improval = true;
        }
    }
    
    private bool background_improval() {
        if (reschedule_improval) {
            reschedule_improval = false;
            
            return true;
        }

        foreach (DataObject object in get_view().get_all()) {
            Thumbnail thumbnail = (Thumbnail) object;
            if (thumbnail.is_exposed())
                thumbnail.paint_high_quality();
        }
        
        improval_scheduled = false;
        
        debug("improve_thumbnail_quality");
        
        return false;
    }
    
    private void on_file_menu() {
        set_item_sensitive("/CollectionMenuBar/FileMenu/Export", get_view().get_selected_count() > 0);
    }
    
    private void on_export() {
        Gee.ArrayList<LibraryPhoto> export_list = new Gee.ArrayList<LibraryPhoto>();
        foreach (DataView view in get_view().get_selected())
            export_list.add(((Thumbnail) view).get_photo());

        if (export_list.size == 0)
            return;

        ExportDialog export_dialog = null;
        if (export_list.size == 1)
            export_dialog = new ExportDialog(_("Export Photo"));
        else
            export_dialog = new ExportDialog(_("Export Photos"));
        
        int scale;
        ScaleConstraint constraint;
        Jpeg.Quality quality;
        if (!export_dialog.execute(out scale, out constraint, out quality))
            return;

        // handle the single-photo case
        if (export_list.size == 1) {
            LibraryPhoto photo = export_list.get(0);
            
            File save_as = ExportUI.choose_file(photo.get_file());
            if (save_as == null)
                return;
                
            spin_event_loop();
            
            try {
                photo.export(save_as, scale, constraint, quality);
            } catch (Error err) {
                AppWindow.error_message(_("Unable to export photo %s: %s").printf(
                    photo.get_file().get_path(), err.message));
            }
            
            return;
        }

        // multiple photos
        File export_dir = ExportUI.choose_dir();
        if (export_dir == null)
            return;
        
        AppWindow.get_instance().set_busy_cursor();
        
        foreach (LibraryPhoto photo in export_list) {
            File save_as = export_dir.get_child(photo.get_file().get_basename());
            if (save_as.query_exists(null)) {
                if (!ExportUI.query_overwrite(save_as))
                    continue;
            }
            
            spin_event_loop();

            try {
                photo.export(save_as, scale, constraint, quality);
            } catch (Error err) {
                AppWindow.error_message(_("Unable to export photo %s: %s").printf(save_as.get_path(),
                    err.message));
            }
        }
        
        AppWindow.get_instance().set_normal_cursor();
    }

    private void on_edit_menu() {
        set_item_sensitive("/CollectionMenuBar/EditMenu/SelectAll", get_view().get_count() > 0);
        set_item_sensitive("/CollectionMenuBar/EditMenu/Remove", get_view().get_selected_count() > 0);
    }
    
    private void on_select_all() {
        get_view().select_all();
    }
    
    private bool can_revert_selected() {
        foreach (DataView view in get_view().get_selected()) {
            LibraryPhoto photo = ((Thumbnail) view).get_photo();
            if (photo.has_transformations())
                return true;
        }
        
        return false;
    }
    
    protected virtual void on_photos_menu() {
        bool selected = (get_view().get_selected_count() > 0);
        bool revert_possible = can_revert_selected();
        
        set_item_sensitive("/CollectionMenuBar/PhotosMenu/IncreaseSize", scale < Thumbnail.MAX_SCALE);
        set_item_sensitive("/CollectionMenuBar/PhotosMenu/DecreaseSize", scale > Thumbnail.MIN_SCALE);
        set_item_sensitive("/CollectionMenuBar/PhotosMenu/RotateClockwise", selected);
        set_item_sensitive("/CollectionMenuBar/PhotosMenu/RotateCounterclockwise", selected);
        set_item_sensitive("/CollectionMenuBar/PhotosMenu/Mirror", selected);
        set_item_sensitive("/CollectionMenuBar/PhotosMenu/Revert", selected && revert_possible);
        set_item_sensitive("/CollectionMenuBar/PhotosMenu/Slideshow", get_view().get_count() > 0);
    }
    
    private void on_increase_size() {
        increase_thumb_size();
        slider.set_value(scale_to_slider(scale));
    }

    private void on_decrease_size() {
        decrease_thumb_size();
        slider.set_value(scale_to_slider(scale));
    }

    private void on_remove() {
        if (get_view().get_selected_count() == 0)
            return;

        string msg_string = _("If you remove these photos from your library you will lose all edits you've made to them.  Shotwell can also delete the files from your drive.\n\nThis action cannot be undone.");

        Gtk.MessageDialog dialog = new Gtk.MessageDialog(AppWindow.get_instance(), Gtk.DialogFlags.MODAL,
            Gtk.MessageType.WARNING, Gtk.ButtonsType.CANCEL, msg_string);
        dialog.add_button(Gtk.STOCK_DELETE, Gtk.ResponseType.NO);
        dialog.add_button(_("Keep files"), Gtk.ResponseType.YES);
        dialog.title = _("Remove photos?");

        Gtk.ResponseType result = (Gtk.ResponseType) dialog.run();
        
        dialog.destroy();
        
        if (result != Gtk.ResponseType.YES && result != Gtk.ResponseType.NO)
            return;
        
        // mark all the sources for the selected view items and destroy them ... note that simply
        // removing the view items does not work here; the source items (i.e. the Photo objects)
        // must be destroyed, which will remove the view items from this view (and all others)
        Marker marker = LibraryPhoto.global.start_marking();
        foreach (DataView view in get_view().get_selected()) {
            LibraryPhoto photo = ((Thumbnail) view).get_photo();
            
            if (result == Gtk.ResponseType.NO)
                photo.delete_original_on_destroy();
            
            marker.mark(photo);
        }
        
        LibraryPhoto.global.destroy_marked(marker);
    }
    
    private void do_rotations(Gee.Iterable<DataView> c, Rotation rotation) {
        foreach (DataView view in c) {
            LibraryPhoto photo = ((Thumbnail) view).get_photo();
            photo.rotate(rotation);
        }
    }

    private void on_rotate_clockwise() {
        do_rotations(get_view().get_selected(), Rotation.CLOCKWISE);
    }
    
    private void on_rotate_counterclockwise() {
        do_rotations(get_view().get_selected(), Rotation.COUNTERCLOCKWISE);
    }
    
    private void on_mirror() {
        do_rotations(get_view().get_selected(), Rotation.MIRROR);
    }
    
    private void on_revert() {
        foreach (DataView view in get_view().get_selected()) {
            LibraryPhoto photo = ((Thumbnail) view).get_photo();
            photo.remove_all_transformations();
        }
    }
    
    private void on_slideshow() {
        if (get_view().get_count() == 0)
            return;
        
        Thumbnail thumbnail = (Thumbnail) get_fullscreen_photo();
        if (thumbnail == null)
            return;

        AppWindow.get_instance().go_fullscreen(new FullscreenWindow(new SlideshowPage(get_view(),
            thumbnail)));
    }

    private void on_view_menu() {
        set_item_sensitive("/CollectionMenuBar/ViewMenu/Fullscreen", get_view().get_count() > 0);
    }
    
    private bool display_titles() {
        Gtk.ToggleAction action = (Gtk.ToggleAction) ui.get_action("/CollectionMenuBar/ViewMenu/ViewTitle");
        
        return action.get_active();
    }
    
    private void on_display_titles(Gtk.Action action) {
        bool display = ((Gtk.ToggleAction) action).get_active();
        
        foreach (DataObject object in get_view().get_all())
            ((Thumbnail) object).display_title(display);
        
        refresh("on_display_titles");
    }
    
    private static double scale_to_slider(int value) {
        assert(value >= Thumbnail.MIN_SCALE);
        assert(value <= Thumbnail.MAX_SCALE);
        
        return (double) ((value - Thumbnail.MIN_SCALE) / SLIDER_STEPPING);
    }
    
    private static int slider_to_scale(double value) {
        int res = ((int) (value * SLIDER_STEPPING)) + Thumbnail.MIN_SCALE;

        assert(res >= Thumbnail.MIN_SCALE);
        assert(res <= Thumbnail.MAX_SCALE);
        
        return res;
    }
    
    private void on_slider_changed() {
        if (!is_in_view()) {
            thumbs_resized = true;
            
            return;
        }
        
        set_thumb_size(slider_to_scale(slider.get_value()));
    }
    
    private override bool on_ctrl_pressed(Gdk.EventKey event) {
        rotate_button.set_stock_id(Resources.COUNTERCLOCKWISE);
        rotate_button.set_label(Resources.ROTATE_CCW_LABEL);
        rotate_button.set_tooltip_text(Resources.ROTATE_CCW_TOOLTIP);
        rotate_button.clicked -= on_rotate_clockwise;
        rotate_button.clicked += on_rotate_counterclockwise;
        
        return false;
    }
    
    private override bool on_ctrl_released(Gdk.EventKey event) {
        rotate_button.set_stock_id(Resources.CLOCKWISE);
        rotate_button.set_label(Resources.ROTATE_CW_LABEL);
        rotate_button.set_tooltip_text(Resources.ROTATE_CW_TOOLTIP);
        rotate_button.clicked -= on_rotate_counterclockwise;
        rotate_button.clicked += on_rotate_clockwise;
        
        return false;
    }
    
    private int get_sort_criteria() {
        // any member of the group knows the current value
        Gtk.RadioAction action = (Gtk.RadioAction) ui.get_action(
            "/CollectionMenuBar/ViewMenu/SortPhotos/SortByName");
        assert(action != null);
        
        int value = action.get_current_value();
        assert(value >= SORT_BY_MIN);
        assert(value <= SORT_BY_MAX);
        
        return value;
    }
    
    private int get_sort_order() {
        // any member of the group knows the current value
        Gtk.RadioAction action = (Gtk.RadioAction) ui.get_action(
            "/CollectionMenuBar/ViewMenu/SortPhotos/SortAscending");
        assert(action != null);
        
        int value = action.get_current_value();
        assert(value >= SORT_ORDER_MIN);
        assert(value <= SORT_ORDER_MAX);
        
        return value;
    }
    
    private bool is_sort_ascending() {
        return get_sort_order() == SORT_ORDER_ASCENDING;
    }
    
    private void on_sort_changed() {
        get_view().set_comparator(get_sort_comparator());
    }
    
    private Comparator<LayoutItem> get_sort_comparator() {
        switch (get_sort_criteria()) {
            case SORT_BY_NAME:
                return new CompareName(is_sort_ascending());
            
            case SORT_BY_EXPOSURE_DATE:
                return new CompareDate(is_sort_ascending());
            
            default:
                error("Unknown sort criteria: %d", get_sort_criteria());
                
                return new CompareName(true);
        }
    }

}

public class LibraryPage : CollectionPage {
    public LibraryPage() {
        base(_("Photos"));
        
        get_view().monitor_source_collection(LibraryPhoto.global, new CollectionViewManager(this));
    }
}

