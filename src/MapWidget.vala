 /* Copyright 2009-2012 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution.
 */

private class PositionMarker : Object {
    public PositionMarker(MapWidget map_widget, DataView view, Champlain.Marker marker) {
        this.view = view;
        // marker.reactive = true;
        marker.selectable = true;
        marker.button_release_event.connect ((event) => {
            if (event.button > 1)
                return true;
            map_widget.select_data_view(this);
            return true;
        });
        marker.enter_event.connect ((event) => {
            map_widget.highlight_data_view(this);
            return true;
        });
        marker.leave_event.connect ((event) => {
            map_widget.unhighlight_data_view(this);
            return true;
        });
        this.marker = marker;
    }

    public Champlain.Marker marker { get; private set; }
    public string location_country { get; set; }
    public string location_city { get; set; }
    public unowned DataView view { get; private set; }
}

private class MapWidget : Gtk.VBox {
    private const int DEFAULT_ZOOM_LEVEL = 8;
    private static MapWidget instance = null;
    private GtkChamplain.Embed map_widget = new GtkChamplain.Embed();
    private Champlain.View map_view = null;
    private Champlain.Scale map_scale = new Champlain.Scale();
    private Champlain.MarkerLayer marker_layer = new Champlain.MarkerLayer();
    private Gdk.Pixbuf gdk_marker = null;
    private Gee.Map<DataView, PositionMarker> position_markers = new Gee.HashMap<DataView, PositionMarker>();
    private unowned Page page = null;

    public static MapWidget get_instance() {
        if (instance == null)
            instance = new MapWidget();
        return instance;
    }

    public void set_page(Page page) {
        this.page = page;
    }

    public void setup_map() {
        // add scale to bottom left corner of the map
        map_view = map_widget.get_view();
        map_view.add_layer(marker_layer);
        map_scale.connect_view(map_view);
        map_view.bin_layout_add(map_scale, Clutter.BinAlignment.START, Clutter.BinAlignment.END);

        map_view.set_zoom_on_double_click(false);
        map_widget.button_press_event.connect(map_zoom_handler);
        map_widget.set_size_request(200, 200);
        this.add(map_widget);

        // Load gdk pixbuf via Resources class
        gdk_marker = Resources.get_icon(Resources.ICON_GPS_MARKER);
    }

    private PositionMarker? create_position_marker(DataView view) {
        DataSource data_source = view.get_source();
        assert(data_source is Photo);
        Photo photo = (Photo) data_source;
        GpsCoords gps_coords = photo.get_gps_coords();
        if (gps_coords.has_gps != 0) {
            Champlain.Marker champlain_marker;
            if (gdk_marker == null) {
                // Fall back to the generic champlain marker
                champlain_marker = new Champlain.Point.full(12, { red:10, green:10, blue:255, alpha:255 });
            } else {
                champlain_marker = new Champlain.CustomMarker();
                try {
                    GtkClutter.Texture marker_texture = new GtkClutter.Texture();
                    marker_texture.set_from_pixbuf(gdk_marker);
                    ((Champlain.CustomMarker) champlain_marker).add_actor(marker_texture);
                } catch (GLib.Error e) {
                    // Fall back to the generic champlain marker
                    champlain_marker = new Champlain.Point.full(12, { red:10, green:10, blue:255, alpha:255 });
                }
            }
            // set_position doesn't work, resort to properties
            //champlain_marker.set_position((float) gps_coords.latitude, (float) gps_coords.longitude);

            champlain_marker.latitude = (float) gps_coords.latitude;
            champlain_marker.longitude = (float) gps_coords.longitude;
            return new PositionMarker(this, view, champlain_marker);
        }
        return null;
    }

    public void clear() {
        marker_layer.remove_all();
        position_markers.clear();
    }

    public void add_position_marker(DataView view) {
        PositionMarker? position_marker = null;
        if (view.get_source() is Photo) {
            position_marker = create_position_marker(view);
        } else {
            // unsupported for now
            // create an interface that enforces get_gps_coords()
            // and implement it for instance in EventSource or VideoSource
        }
        if (position_marker != null) {
            add_marker(position_marker.marker);
            position_markers.set(view, position_marker);
        }
    }

    public void show_position_markers() {
        if (marker_layer.get_markers().first() != null) {
            Champlain.BoundingBox bbox = marker_layer.get_bounding_box();
            if (map_view.get_zoom_level() < DEFAULT_ZOOM_LEVEL) {
                map_view.set_zoom_level(DEFAULT_ZOOM_LEVEL);
            }
            map_view.ensure_visible(bbox, true);
        }
    }

    public void select_data_view(PositionMarker m) {
        ViewCollection page_view = null;
        if (page != null)
            page_view = page.get_view();
        if (page_view != null) {
           Marker marked = page_view.start_marking();
           marked.mark(m.view);
           page_view.unselect_all();
           page_view.select_marked(marked);
        }
    }

    public void highlight_data_view(PositionMarker m) {
        if (page != null) {
            CheckerboardItem item = (CheckerboardItem) m.view;

            // if item is in any way out of view, scroll to it
            Gtk.Adjustment vadj = page.get_vadjustment();

            if (!(get_adjustment_relation(vadj, item.allocation.y) == AdjustmentRelation.IN_RANGE
                && (get_adjustment_relation(vadj, item.allocation.y + item.allocation.height) == AdjustmentRelation.IN_RANGE))) {

                // scroll to see the new item
                int top = 0;
                if (item.allocation.y < vadj.get_value()) {
                    top = item.allocation.y;
                    top -= CheckerboardLayout.ROW_GUTTER_PADDING / 2;
                } else {
                    top = item.allocation.y + item.allocation.height - (int) vadj.get_page_size();
                    top += CheckerboardLayout.ROW_GUTTER_PADDING / 2;
                }

                vadj.set_value(top);
            }
            item.brighten();
        }
    }

    public void unhighlight_data_view(PositionMarker m) {
        if (page != null) {
            CheckerboardItem item = (CheckerboardItem) m.view;
            item.unbrighten();
        }
    }

    public void highlight_position_marker(DataView v) {
        PositionMarker? m = position_markers.get(v);
        if (m != null) {
            m.marker.set_selected(true);
        }
    }

    public void unhighlight_position_marker(DataView v) {
        PositionMarker? m = position_markers.get(v);
        if (m != null) {
            m.marker.set_selected(false);
        }
    }

    private void add_marker(Champlain.Marker marker) {
        marker_layer.add_marker(marker);
    }

    private bool map_zoom_handler(Gdk.EventButton event) {
        if (event.type == Gdk.EventType.2BUTTON_PRESS) {
            if (event.button == 1 || event.button == 3) {
                double lat = map_view.y_to_latitude(event.y);
                double lon = map_view.x_to_longitude(event.x);
                if (event.button == 1) {
                    map_view.zoom_in();
                } else {
                    map_view.zoom_out();
                }
                map_view.center_on(lat, lon);
                return true;
            }
        }
        return false;
    }
}
