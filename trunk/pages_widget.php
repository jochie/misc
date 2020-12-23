<?php
/*
Plugin Name: Custom Pages Widget
Description: A configurable pages section in your sidebar.
Author: Erwin Harte
Version: 1.1
Author URI: http://is-here.com/projects/wordpress/pages
Credits: Calvin Yu (http://blog.codeeg.com/)
*/

function widget_custom_pages_init() {
    if (!function_exists("register_sidebar_widget")) {
	return;
    }

function widget_custom_pages($args) {
    extract($args);

    $options = get_option("widget_custom_pages");
    $title    = empty($options['title']) ? __('Pages')          : $options['title'];
    $depth    = empty($options['depth']) ? '0'                  : $options['depth'];
    $sort_col = empty($options['sort_col'])  ? __('post_title') : $options['sort_col'];
    $sort_ord = empty($options['sort_ord'])  ? __('ASC')        : $options['sort_ord'];
    $exclude  = empty($options['exclude'])  ? ''                : $options['exclude'];

    echo $before_widget . $before_title . $title . $after_title . '<ul>';

    wp_list_pages("title_li=&sort_order=$sort_ord&sort_column=$sort_col&depth=$depth&exclude=$exclude");
    echo '</ul>' . $after_widget;
}

function widget_custom_pages_control() {
    $options = $newoptions = get_option("widget_custom_pages");
    if ( $_POST['custom-pages-submit'] ) {
	$newoptions['depth']     = strip_tags(stripslashes($_POST['custom-pages-depth']));
	$newoptions['title']     = strip_tags(stripslashes($_POST['custom-pages-title']));
	$newoptions['sort_col']  = strip_tags(stripslashes($_POST['custom-pages-sort-col']));
	$newoptions['sort_ord']  = strip_tags(stripslashes($_POST['custom-pages-sort-ord']));
	$newoptions['exclude']   = strip_tags(stripslashes($_POST['custom-pages-exclude']));
    }
    if ( $options != $newoptions ) {
	$options = $newoptions;
	update_option('widget_custom_pages', $options);
    }
    $depth    = wp_specialchars($options['depth']);
    $title    = wp_specialchars($options['title']);
    $sort_col = wp_specialchars($options['sort_col']);
    $sort_ord = wp_specialchars($options['sort_ord']);
    $exclude  = wp_specialchars($options['exclude']);
?>
<div style="text-align:right">
  <label for="custom-pages-title" style="line-height:35px;display:block;">Widget Title:
    <input id="custom-pages-title" name="custom-pages-title" type="text" value="<?php echo htmlspecialchars($title); ?>" />
  </label>
  <label for="custom-pages-depth" style="line-height:35px;display:block;">Depth:
    <input id="custom-pages-depth" name="custom-pages-depth" type="text" value="<?php echo htmlspecialchars($depth); ?>" />
  </label>
  <label for="custom-pages-exclude" style="line-height:35px;display:block;">Exclude:
    <input id="custom-pages-exclude" name="custom-pages-exclude" type="text" value="<?php echo htmlspecialchars($exclude); ?>" />
  </label>
  <label for="custom-pages-sort-col" style="line-height:30px;display:block;">Sort on:
    <select name="custom-pages-sort-col" id="custom-pages-sort-col">
      <option <?php if ($sort_col == 'post_title') echo 'selected="selected" ' ?>value="post_title">Page Title</option>
      <option <?php if ($sort_col == 'menu_order') echo 'selected="selected" ' ?>value="menu_order">Page Order</option>
    </select>
  </label>
  <label for="custom-pages-sort-ord" style="line-height:30px;display:block;">Sort:
    <select name="custom-pages-sort-ord" id="custom-pages-sort-ord">
      <option <?php if ($sort_ord == 'ASC') echo 'selected="selected" ' ?>value="ASC">Ascending</option>
      <option <?php if ($sort_ord == 'DESC') echo 'selected="selected" ' ?>value="DESC">Descending</option>
    </select>
  </label>
  <input type="hidden" id="custom-pages-submit" name="custom-pages-submit" value="1" />
</div>
<?php
}

    register_sidebar_widget("Custom Pages", "widget_custom_pages");
    register_widget_control("Custom Pages", "widget_custom_pages_control");
}

add_action("plugins_loaded", "widget_custom_pages_init");

?>
