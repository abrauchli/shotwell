 /* Copyright 2009-2012 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution.
 */

private class Marker : Object {
    public Marker(unowned Photo photo, Champlain.Marker marker) {
        this.photo = photo;
        marker.reactive = true;
        marker.button_release_event.connect ((event) => {
            // TODO: select this photo
            return true;
        });
        this.marker = marker;
    }

    unowned Photo photo;
    Champlain.Marker? marker;
    string location_country;
    string location_city;
}

private class MapWidget : Gtk.VBox box {
    private GtkChamplain.Embed map_widget = new GtkChamplain.Embed();
    private Champlain.View map_view = null;
    private Champlain.Scale map_scale = new Champlain.Scale();
    private Champlain.MarkerLayer marker_layer = new Champlain.MarkerLayer();
    private Gdk.Pixbuf gdk_marker = null;

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

    private Marker? create_gps_marker(Photo photo) {
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
            return new Marker(photo, champlain_marker);
        }
        return null;
    }

    public void clear() {
        marker_layer.remove_all();
    }

    public void add_marker(Photo source) {
        Marker? marker = create_gps_marker(source);
        if (marker != null)
            add_gps_marker(marker);
    }

    public void show_markers() {
        if (marker_layer.get_markers().first() != null) {
            Champlain.BoundingBox bbox = marker_layer.get_bounding_box();
            map_view.ensure_visible(bbox, true);
        }
    }

    private void add_gps_marker(Champlain.Marker marker) {
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
