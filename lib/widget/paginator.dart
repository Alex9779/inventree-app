import "package:flutter/material.dart";

import "package:font_awesome_flutter/font_awesome_flutter.dart";
import "package:infinite_scroll_pagination/infinite_scroll_pagination.dart";

import "package:inventree/api_form.dart";
import "package:inventree/l10.dart";

import "package:inventree/inventree/model.dart";
import "package:inventree/inventree/sentry.dart";
import "package:inventree/preferences.dart";

import "package:inventree/widget/refreshable_state.dart";


/*
 * Generic stateful widget for displaying paginated data retrieved via the API
 *
 * - Can be displayed as "full screen" (with app-bar and drawer)
 * - Can be displayed as a standalone widget
 */
class PaginatedSearchState<T extends StatefulWidget> extends State<T> with BaseWidgetProperties {

  PaginatedSearchState(this.filters, {this.fullscreen = true});

  final _key = GlobalKey<ScaffoldState>();

  final Map<String, String> filters;

  static const _pageSize = 25;

  // Determine if this widget is shown "fullscreen" (i.e. with appbar)
  final bool fullscreen;

  // Prefix for storing and loading pagination options
  // Override in implementing class
  String get prefix => "prefix_";

  // Return a map of sorting options available for this list
  // Should be overridden by an implementing subclass
  Map<String, String> get orderingOptions => {};

  // Return the selected ordering "field" for this list widget
  Future<String> orderingField() async {
    dynamic field = await InvenTreeSettingsManager().getValue("${prefix}ordering_field", null);

    if (field != null && orderingOptions.containsKey(field.toString())) {
      // A valid ordering field has been found
      return field.toString();
    } else if (orderingOptions.isNotEmpty) {
      // By default, return the first specified key
      return orderingOptions.keys.first;
    } else {
      return "";
    }
  }

  // Return the selected ordering "order" ("+" or "-") for this list widget
  Future<String> orderingOrder() async {
    dynamic order = await InvenTreeSettingsManager().getValue("${prefix}ordering_order", "+");

    return order == "+" ? "+" : "-";
  }

  // Return string for determining 'ordering' of paginated list
  Future<String> get orderingString async {
    dynamic field = await orderingField();
    dynamic order = await orderingOrder();

    // Return an empty string if no field is provided
    if (field.toString().isEmpty) {
      return "";
    }

    return "${order}${field}";
  }

  // Update the (configurable) filters for this paginated list
  Future<void> _saveOrderingOptions(BuildContext context) async {
    // Retrieve stored setting
    dynamic _field = await orderingField();
    dynamic _order = await orderingOrder();

    // Construct the 'ordering' options
    List<Map<String, dynamic>> _opts = [];

    orderingOptions.forEach((k, v) => _opts.add({
      "value": k.toString(),
      "display_name": v.toString()
    }));

    if (_field == null && _opts.isNotEmpty) {
      _field = _opts.first["value"];
    }

    Map<String, dynamic> fields = {
      "ordering_field": {
        "type": "choice",
        "label": "Ordering Field",
        "required": true,
        "choices": _opts,
        "value": _field,
      },
      "ordering_order": {
        "type": "choice",
        "label": "Ordering Direction",
        "required": true,
        "value": _order,
        "choices": [
          {
          "value": "+",
          "display_name": "Ascending",
          },
          {
          "value": "-",
          "display_name": "Descending",
          }
        ]
      }
    };

    launchApiForm(
      context,
      "...filtering...",
      "",
      fields,
      icon: FontAwesomeIcons.checkCircle,
      onSuccess: (Map<String, dynamic> data) async {

        // Extract data from the processed form
        String f = (data["ordering_field"] ?? _field) as String;
        String o = (data["ordering_order"] ?? _order) as String;

        // Save values to settings
        await InvenTreeSettingsManager().setValue("${prefix}ordering_field", f);
        await InvenTreeSettingsManager().setValue("${prefix}ordering_order", o);

        // Refresh data from the server
        _pagingController.refresh();
      }
    );
  }

  // Search query term
  String searchTerm = "";

  int resultCount = 0;

  // Text controller
  final TextEditingController searchController = TextEditingController();

  // Pagination controller
  final PagingController<int, InvenTreeModel> _pagingController = PagingController(firstPageKey: 0);

  @override
  void initState() {
    _pagingController.addPageRequestListener((pageKey) {
      _fetchPage(pageKey);
    });

    super.initState();
  }

  @override
  void dispose() {
    _pagingController.dispose();
    super.dispose();
  }

  Future<InvenTreePageResponse?> requestPage(int limit, int offset, Map<String, String> params) async {

    // Default implementation returns null - must be overridden
    return null;
  }

  Future<void> _fetchPage(int pageKey) async {
    try {
      Map<String, String> params = filters;

      params["search"] = "${searchTerm}";
      params["ordering"] = await orderingString;

      final page = await requestPage(
        _pageSize,
        pageKey,
        params
      );

      int pageLength = page?.length ?? 0;
      int pageCount = page?.count ?? 0;

      final isLastPage = pageLength < _pageSize;

      List<InvenTreeModel> items = [];

      if (page != null) {
        for (var result in page.results) {
            items.add(result);
        }
      }

      if (isLastPage) {
        _pagingController.appendLastPage(items);
      } else {
        final int nextPageKey = pageKey + pageLength;
        _pagingController.appendPage(items, nextPageKey);
      }

      setState(() {
        resultCount = pageCount;
      });
    } catch (error, stackTrace) {
      _pagingController.error = error;

      sentryReportError(
        "paginator.fetchPage",
        error, stackTrace,
      );
    }
  }

  void updateSearchTerm() {
    searchTerm = searchController.text;
    _pagingController.refresh();
  }

  // Function to construct a single paginated item
  // Must be overridden in an implementing subclass
  Widget buildItem(BuildContext context, InvenTreeModel item) {

    // This method must be overridden by the child class
    return ListTile(
      title: Text("*** UNIMPLEMENTED ***"),
      subtitle: Text("*** buildItem() is unimplemented for this widget!"),
    );
  }

  // Return a string which is displayed when there are no results
  // Can be overridden by an implementing subclass
  String get noResultsText => L10().noResults;

  @override
  Widget build (BuildContext context) {

    if (fullscreen) {
      return Scaffold(
        key: _key,
        appBar: buildAppBar(context, _key),
        drawer: getDrawer(context),
        body: Builder(
          builder: (BuildContext ctx) {
            return getBody(ctx);
          }
        )
      );
    } else {
      return getBody(context);
    }
  }

  @override
  Widget getBody(BuildContext context) {
    return Column(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          PaginatedSearchWidget(searchController, updateSearchTerm, resultCount),
          Expanded(
              child: CustomScrollView(
                  shrinkWrap: true,
                  physics: ClampingScrollPhysics(),
                  scrollDirection: Axis.vertical,
                  slivers: <Widget>[
                    // TODO - Search input
                    PagedSliverList.separated(
                      pagingController: _pagingController,
                      builderDelegate: PagedChildBuilderDelegate<InvenTreeModel>(
                          itemBuilder: (context, item, index) {
                            return buildItem(context, item);
                          },
                          noItemsFoundIndicatorBuilder: (context) {
                            return NoResultsWidget(noResultsText);
                          }
                      ),
                      separatorBuilder: (context, item) => const Divider(height: 1),
                    )
                  ]
              )
          )
        ]
    );
  }

  @override
  List<Widget> getAppBarActions(BuildContext context) {
    List<Widget> actions = [];

    // If ordering options have been provided
    if (orderingOptions.isNotEmpty) {
      actions.add(IconButton(
        icon: FaIcon(FontAwesomeIcons.sort),
        onPressed: () => _saveOrderingOptions(context),
      ));
    }

    return actions;
  }

}


class PaginatedSearchWidget extends StatelessWidget {

  const PaginatedSearchWidget(this.controller, this.onChanged, this.results);

  final Function onChanged;

  final int results;

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: GestureDetector(
        child: FaIcon(controller.text.isEmpty ? FontAwesomeIcons.search : FontAwesomeIcons.backspace),
        onTap: () {
          controller.clear();
          onChanged();
        },
      ),
      title: TextFormField(
        controller: controller,
        onChanged: (value) {
          onChanged();
        },
        decoration: InputDecoration(
          hintText: L10().search,
        ),
      ),
      trailing: Text(
        "${results}",
        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontStyle: FontStyle.italic
        ),
      ),
    );
  }
}

class NoResultsWidget extends StatelessWidget {

  const NoResultsWidget(this.description);

  final String description;

  @override
  Widget build(BuildContext context) {

    return ListTile(
      title: Text(L10().noResults),
      subtitle: Text(description),
      leading: FaIcon(FontAwesomeIcons.exclamationCircle),
    );
  }

}
