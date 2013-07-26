/* Copyright 2011-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public interface Sidebar.Entry : Object {
    public signal void sidebar_tooltip_changed(string? tooltip);
    
    public signal void sidebar_icon_changed(Icon? icon);
    
    public abstract string get_sidebar_name();
    
    public abstract string? get_sidebar_tooltip();
    
    public abstract Icon? get_sidebar_icon();
    
    public abstract string to_string();
    
    internal virtual void grafted(Sidebar.Tree tree) {
    }
    
    internal virtual void pruned(Sidebar.Tree tree) {
    }
}

public interface Sidebar.ExpandableEntry : Sidebar.Entry {
    public signal void sidebar_open_closed_icons_changed(Icon? open, Icon? closed);
    
    public abstract Icon? get_sidebar_open_icon();
    
    public abstract Icon? get_sidebar_closed_icon();
    
    public abstract bool expand_on_select();
}

public interface Sidebar.SelectableEntry : Sidebar.Entry {
}

public interface Sidebar.PageRepresentative : Sidebar.Entry, Sidebar.SelectableEntry {
    // Fired after the page has been created
    public signal void page_created(Page page);
    
    // Fired before the page is destroyed.
    public signal void destroying_page(Page page);
    
    public abstract bool has_page();
    
    public abstract Page get_page();
}

public interface Sidebar.RenameableEntry : Sidebar.Entry {
    public signal void sidebar_name_changed(string name);
    
    public abstract void rename(string new_name);
}

public interface Sidebar.DestroyableEntry : Sidebar.Entry {
    public abstract void destroy_source();
}

public interface Sidebar.InternalDropTargetEntry : Sidebar.Entry {
    // Returns true if drop was successful
    public abstract bool internal_drop_received(Gee.List<MediaSource> sources);
    public abstract bool internal_drop_received_arbitrary(Gtk.SelectionData data);
}

public interface Sidebar.InternalDragSourceEntry : Sidebar.Entry {
    public abstract void prepare_selection_data(Gtk.SelectionData data);
}
