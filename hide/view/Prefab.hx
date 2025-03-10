package hide.view;
import hide.view.CameraController.CamController;
using Lambda;

import hxd.Math;
import hxd.Key as K;

import hrt.prefab.Prefab as PrefabElement;
import hrt.prefab.Object3D;
import hrt.prefab.l3d.Instance;
import hide.comp.cdb.DataFiles;



@:access(hide.view.Prefab)
private class PrefabSceneEditor extends hide.comp.SceneEditor {
	var parent : Prefab;

	public function new(view, data) {
		super(view, data);
		parent = cast view;
		this.localTransform = false; // TODO: Expose option
	}

	override function refresh(?mode, ?callback) {
		parent.onRefresh();
		super.refresh(mode, callback);
	}

	override function update(dt) {
		super.update(dt);
		parent.onUpdate(dt);
	}

	override function onSceneReady() {
		super.onSceneReady();
		parent.onSceneReady();
	}

	override function applyTreeStyle(p: PrefabElement, el: Element, ?pname: String) {
		super.applyTreeStyle(p, el, pname);
		parent.applyTreeStyle(p, el, pname);
	}

	override function applySceneStyle(p:PrefabElement) {
		parent.applySceneStyle(p);
	}

	override function onPrefabChange(p: PrefabElement, ?pname: String) {
		super.onPrefabChange(p, pname);
		parent.onPrefabChange(p, pname);
	}

	override function getNewContextMenu(current: PrefabElement, ?onMake: PrefabElement->Void=null, ?groupByType = true ) {
		var newItems = super.getNewContextMenu(current, onMake, groupByType);
		var recents = getNewRecentContextMenu(current, onMake);

		function setup(p : PrefabElement) {
			autoName(p);
			haxe.Timer.delay(addElements.bind([p]), 0);
		}

		function addNewInstances() {
			var items = new Array<hide.comp.ContextMenu.ContextMenuItem>();
			for(type in DataFiles.getAvailableTypes() ) {
				var typeId = DataFiles.getTypeName(type);
				var label = typeId.charAt(0).toUpperCase() + typeId.substr(1);

				var refCols = Instance.findRefColumns(type);
				var refSheet = refCols == null ? null : type.base.getSheet(refCols.sheet);
				var idCol = refCols == null ? null : Instance.findIDColumn(refSheet);

				function make(name) {
					var p = new Instance(current == null ? sceneData : current);
					p.name = name;
					p.props = makeCdbProps(p, type);
					setup(p);
					if(onMake != null)
						onMake(p);
					return p;
				}

				if(idCol != null && refSheet.props.dataFiles == null ) {
					var kindItems = new Array<hide.comp.ContextMenu.ContextMenuItem>();
					for(line in refSheet.lines) {
						var kind : String = Reflect.getProperty(line, idCol.name);
						kindItems.push({
							label : kind,
							click : function() {
								var p = make(kind.charAt(0).toLowerCase() + kind.substr(1));
								var obj : Dynamic = p.props;
								for( c in refCols.cols ) {
									if( c == refCols.cols[refCols.cols.length-1] )
										Reflect.setField(obj, c.name, kind);
									else {
										var s = Reflect.field(obj,c.name);
										if( s == null ) {
											s = {};
											Reflect.setField(obj, c.name, s);
										}
										obj = s;
									}
								}
							}
						});
					}
					items.unshift({
						label : label,
						menu: kindItems
					});
				}
				else {
					items.push({
						label : label,
						click : make.bind(typeId)
					});
				}
			}
			newItems.unshift({
				label : "Instance",
				menu: items
			});
		};
		addNewInstances();
		newItems.unshift({
			label : "Recents",
			menu : recents,
		});
		return newItems;
	}

	override function getAvailableTags(p:PrefabElement) {
		return cast ide.currentConfig.get("sceneeditor.tags");
	}
}

class Prefab extends FileView {

	public var sceneEditor : PrefabSceneEditor;
	var data : hrt.prefab.Library;

	var tools : hide.comp.Toolbar;

	var layerToolbar : hide.comp.Toolbar;
	var layerButtons : Map<PrefabElement, hide.comp.Toolbar.ToolToggle>;

	var resizablePanel : hide.comp.ResizablePanel;

	var grid : h3d.scene.Graphics;

	var gridStep : Float = 0.;
	var gridSize : Int;
	var showGrid = false;

	// autoSync
	var autoSync : Bool;
	var currentVersion : Int = 0;
	var lastSyncChange : Float = 0.;
	var sceneFilters : Map<String, Bool>;
	var graphicsFilters : Map<String, Bool>;
	var statusText : h2d.Text;
	var posToolTip : h2d.Text;

	var scene(get, null):  hide.comp.Scene;
	function get_scene() return sceneEditor.scene;
	public var properties(get, null):  hide.comp.PropsEditor;
	function get_properties() return sceneEditor.properties;

	override function onDisplay() {
		if( sceneEditor != null ) sceneEditor.dispose();

		data = new hrt.prefab.Library();
		var content = sys.io.File.getContent(getPath());
		data.loadData(haxe.Json.parse(content));
		currentSign = ide.makeSignature(content);

		element.html('
			<div class="flex vertical">
				<div style="flex: 0 0 30px;">
					<span class="prefab-toolbar"></span>
				</div>

				<div class="scene-partition" style="display: flex; flex-direction: row; flex: 1; overflow: hidden;">
					<div class="heaps-scene"></div>
					<div class="tree-column">
						<div class="flex vertical">
							<div class="hide-toolbar">
								<div class="toolbar-label">
									<div class="icon ico ico-sitemap"></div>
									Scene
								</div>
								<div class="button collapse-btn" title="Collapse all">
									<div class="icon ico ico-reply-all"></div>
								</div>

								<div class="button combine-btn layout-btn" title="Toggle columns layout">
									<div class="icon ico ico-compress"></div>
								</div>
								<div class="button separate-btn layout-btn" title="Toggle columns layout">
									<div class="icon ico ico-expand"></div>
								</div>

								<div
									class="button hide-cols-btn close-btn"
									title="Hide Tree & Props (${config.get("key.sceneeditor.toggleLayout")})"
								>
									<div class="icon ico ico-chevron-right"></div>
								</div>
							</div>

							<div class="hide-scenetree"></div>
						</div>
					</div>

					<div class="props-column">
						<div class="hide-toolbar">
							<div class="toolbar-label">
								<div class="icon ico ico-sitemap"></div>
								Properties
							</div>
						</div>
							<div class="hide-scroll"></div>
					</div>

					<div
						class="button show-cols-btn close-btn"
						title="Show Tree & Props (${config.get("key.sceneeditor.toggleLayout")})"
					>
						<div class="icon ico ico-chevron-left"></div>
					</div>
				</div>
			</div>
		');

		tools = new hide.comp.Toolbar(null,element.find(".prefab-toolbar"));
		layerToolbar = new hide.comp.Toolbar(null,element.find(".layer-buttons"));
		currentVersion = undo.currentID;

		sceneEditor = new PrefabSceneEditor(this, data);
		element.find(".hide-scenetree").first().append(sceneEditor.tree.element);
		element.find(".hide-scroll").first().append(properties.element);
		element.find(".heaps-scene").first().append(scene.element);

		var treeColumn = element.find(".tree-column").first();
		resizablePanel = new hide.comp.ResizablePanel(Horizontal, treeColumn);
		resizablePanel.saveDisplayKey = "treeColumn";
		resizablePanel.onResize = () -> @:privateAccess if( scene.window != null) scene.window.checkResize();

		sceneEditor.tree.element.addClass("small");

		refreshColLayout();
		element.find(".combine-btn").first().click((_) -> setCombine(true));
		element.find(".separate-btn").first().click((_) -> setCombine(false));

		element.find(".show-cols-btn").first().click(showColumns);
		element.find(".hide-cols-btn").first().click(hideColumns);

		element.find(".collapse-btn").click(function(e) {
			sceneEditor.collapseTree();
		});

		keys.register("sceneeditor.toggleLayout", () -> {
			if( element.find(".tree-column").first().css('display') == 'none' )
				showColumns();
			else
				hideColumns();
		});

		refreshSceneFilters();
		refreshGraphicsFilters();
	}

	function refreshColLayout() {
		var config = ide.ideConfig;
		if( config.sceneEditorLayout == null ) {
			config.sceneEditorLayout = {
				colsVisible: true,
				colsCombined: false,
			};
		}
		setCombine(config.sceneEditorLayout.colsCombined);

		if( config.sceneEditorLayout.colsVisible )
			showColumns();
		else
			hideColumns();
		if (resizablePanel != null) resizablePanel.setSize();
	}

	override function onActivate() {
		if( element == null )
			return;
		if( sceneEditor != null )
			refreshColLayout();
	}

	function hideColumns(?_) {
		element.find(".tree-column").first().hide();
		element.find(".props-column").first().hide();
		element.find(".splitter").first().hide();
		element.find(".show-cols-btn").first().show();
		ide.ideConfig.sceneEditorLayout.colsVisible = false;
		@:privateAccess ide.config.global.save();
		@:privateAccess if( scene.window != null) scene.window.checkResize();
	}

	function showColumns(?_) {
		element.find(".tree-column").first().show();
		element.find(".props-column").first().show();
		element.find(".splitter").first().show();
		element.find(".show-cols-btn").first().hide();
		ide.ideConfig.sceneEditorLayout.colsVisible = true;
		@:privateAccess ide.config.global.save();
		@:privateAccess if( scene.window != null) scene.window.checkResize();
	}

	function setCombine(val) {
		var fullscene = element.find(".scene-partition").first();
		var props = element.find(".props-column").first();
		fullscene.toggleClass("reduced-columns", val);
		if( val ) {
			element.find(".hide-scenetree").first().parent().append(props);
			element.find(".combine-btn").first().hide();
			element.find(".separate-btn").first().show();
			resizablePanel.setSize();
		} else {
			fullscene.append(props);
			element.find(".combine-btn").first().show();
			element.find(".separate-btn").first().hide();
		}
		ide.ideConfig.sceneEditorLayout.colsCombined = val;
		@:privateAccess ide.config.global.save();
		@:privateAccess if( scene.window != null) scene.window.checkResize();
	}

	public function onSceneReady() {
		tools.saveDisplayKey = "Prefab/toolbar";
		statusText = new h2d.Text(hxd.res.DefaultFont.get(), scene.s2d);
		statusText.setPosition(5, 5);
		statusText.visible = false;
		gridStep = @:privateAccess sceneEditor.gizmo.moveStep;
		sceneEditor.updateGrid = function(step) {
			gridStep = step;
			@:privateAccess sceneEditor.gizmo.moveStep = gridStep;
			updateGrid();
		};
		var toolsDefs = new Array<hide.comp.Toolbar.ToolDef>();
		toolsDefs.push({id: "perspectiveCamera", title : "Perspective camera", icon : "video-camera", type : Button(() -> resetCamera(false)) });
		toolsDefs.push({id: "topCamera", title : "Top camera", icon : "video-camera", iconStyle: { transform: "rotateZ(90deg)" }, type : Button(() -> resetCamera(true))});
		toolsDefs.push({id: "snapToGroundToggle", title : "Snap to ground", icon : "anchor", type : Toggle((v) -> sceneEditor.snapToGround = v)});
		toolsDefs.push({id: "translationMode", title : "Gizmo translation Mode", icon : "arrows", type : Button(@:privateAccess sceneEditor.gizmo.translationMode), rightClick: () -> {
			var items = [{
				label : "Snap to Grid",
				click : function() {
					@:privateAccess sceneEditor.gizmo.snapToGrid = !sceneEditor.gizmo.snapToGrid;
				},
				checked: @:privateAccess sceneEditor.gizmo.snapToGrid
			}];
			var steps : Array<Float> = sceneEditor.view.config.get("sceneeditor.gridSnapSteps");
			for (step in steps) {
				items.push({
					label : ""+step,
					click : function() {
						sceneEditor.updateGrid(step);
					},
					checked: gridStep == step
				});
			}
			new hide.comp.ContextMenu(items);
		}});
		toolsDefs.push({id: "rotationMode", title : "Gizmo rotation Mode", icon : "undo", type : Button(@:privateAccess sceneEditor.gizmo.rotationMode),  rightClick: () -> {
			var steps : Array<Float> = sceneEditor.view.config.get("sceneeditor.rotateStepCoarses");
			var items = [{
				label : "Snap enabled",
				click : function() {
					@:privateAccess sceneEditor.gizmo.rotateSnap = !sceneEditor.gizmo.rotateSnap;
				},
				checked: @:privateAccess sceneEditor.gizmo.rotateSnap
			}];
			for (step in steps) {
				items.push({
					label : ""+step+"°",
					click : function() {
						@:privateAccess sceneEditor.gizmo.rotateStepCoarse = step;
					},
					checked: @:privateAccess sceneEditor.gizmo.rotateStepCoarse == step
				});
			}
			new hide.comp.ContextMenu(items);
		}});
		toolsDefs.push({id: "scalingMode", title : "Gizmo scaling Mode", icon : "compress", type : Button(@:privateAccess sceneEditor.gizmo.scalingMode)});
		toolsDefs.push({id: "localTransformsToggle", title : "Local transforms", icon : "compass", type : Toggle((v) -> sceneEditor.localTransform = v)});
		toolsDefs.push({id: "gridToggle", title : "Toggle grid", icon : "th", type : Toggle((v) -> { showGrid = v; updateGrid(); }) });
		var texContent : Element = null;
		toolsDefs.push({id: "sceneInformationToggle", title : "Scene information", icon : "info-circle", type : Toggle((b) -> statusText.visible = b), rightClick: () -> {
			if( texContent != null ) {
				texContent.remove();
				texContent = null;
			}
			new hide.comp.ContextMenu([
				{
					label : "Show Texture Details",
					click : function() {
						var memStats = scene.engine.mem.stats();
						var texs = @:privateAccess scene.engine.mem.textures;
						var list = [for(t in texs) {
							n: '${t.width}x${t.height}  ${t.format}  ${t.name}',
							size: t.width * t.height
						}];
						list.sort((a, b) -> Reflect.compare(b.size, a.size));
						var content = new Element('<div tabindex="1" class="overlay-info"><h2>Scene info</h2><pre></pre></div>');
						new Element(element[0].ownerDocument.body).append(content);
						var pre = content.find("pre");
						pre.text([for(l in list) l.n].join("\n"));
						texContent = content;
						content.blur(function(_) {
							content.remove();
							texContent = null;
						});
					}
				}
			]);
		}});
		toolsDefs.push({id: "autoSyncToggle", title : "Auto synchronize", icon : "refresh", type : Toggle((b) -> autoSync = b)});
		toolsDefs.push({
			id: "wireframeToggle",
			title: "Wireframe",
			icon: "connectdevelop",
			type: Toggle((b) -> { sceneEditor.setWireframe(b); }),
		});
		toolsDefs.push({id: "backgroundColor", title : "Background Color", type : Color(function(v) {
			scene.engine.backgroundColor = v;
			updateGrid();
		})});
		toolsDefs.push({id: "graphicsFilters", title : "Graphics filters", type : Menu(filtersToMenuItem(graphicsFilters, "Graphics"))});
		toolsDefs.push({id: "sceneFilters", title : "Scene filters", type : Menu(filtersToMenuItem(sceneFilters, "Scene"))});
		toolsDefs.push({id: "sceneSpeed", title : "Speed", type : Range((v) -> scene.speed = v)});

		for (tool in toolsDefs) {
			var key = config.get("key.sceneeditor." + tool.id);
			var shortcut = key != null ? " (" + key + ")" : "";
			var el : Element = null;
			switch(tool.type) {
				case Button(f):
					el = tools.addButton(tool.icon, tool.title + shortcut, f, tool.rightClick);
				case Toggle(f):
					var toggle = tools.addToggle(tool.icon, tool.title + shortcut, f);
					el = toggle.element;
					if( key != null )
						keys.register("sceneeditor." + tool.id, () -> toggle.toggle(!toggle.isDown()));
					if (tool.rightClick != null)
						toggle.rightClick(tool.rightClick);
				case Color(f):
					el = tools.addColor(tool.title, f).element;
				case Range(f):
					el = tools.addRange(tool.title, f, 1.).element;
				case Menu(items):
					var menu = tools.addMenu(tool.icon, tool.title);
					menu.setContent(items);
					el = menu.element;
			}

			el.addClass(tool.id);
			if(tool.iconStyle != null)
				el.find(".icon").css(tool.iconStyle);
		}
		posToolTip = new h2d.Text(hxd.res.DefaultFont.get(), scene.s2d);
		posToolTip.dropShadow = { dx : 1, dy : 1, color : 0, alpha : 0.5 };

		updateStats();
		updateGrid();
		initGraphicsFilters();
	}

	function updateStats() {
		if( statusText.visible ) {
			var memStats = scene.engine.mem.stats();
			@:privateAccess
			var lines : Array<String> = [
				'Scene objects: ${scene.s3d.getObjectsCount()}',
				'Interactives: ' + sceneEditor.interactives.count(),
				'Contexts: ' + sceneEditor.context.shared.contexts.count(),
				'Triangles: ${scene.engine.drawTriangles}',
				'Buffers: ${memStats.bufferCount}',
				'Textures: ${memStats.textureCount}',
				'FPS: ${Math.round(scene.engine.realFps)}',
				'Draw Calls: ${scene.engine.drawCalls}',
			];
			statusText.text = lines.join("\n");
		}
		haxe.Timer.delay(function() sceneEditor.event.wait(0.5, updateStats), 0);
	}

	function resetCamera( top : Bool ) {
		var targetPt = new h3d.col.Point(0, 0, 0);
		var curEdit = sceneEditor.curEdit;
		if(curEdit != null && curEdit.rootObjects.length > 0) {
			targetPt = curEdit.rootObjects[0].getAbsPos().getPosition().toPoint();
		}
		if(top)
			sceneEditor.cameraController.set(200, Math.PI/2, 0.001, targetPt);
		else
			sceneEditor.cameraController.set(200, -4.7, 0.8, targetPt);
		sceneEditor.cameraController.toTarget();
	}

	override function getDefaultContent() {
		return haxe.io.Bytes.ofString(ide.toJSON(new hrt.prefab.Library().saveData()));
	}

	override function canSave() {
		return data != null;
	}

	override function save() {
		if( !canSave() )
			return;
		var content = ide.toJSON(data.saveData());
		var newSign = ide.makeSignature(content);
		if(newSign != currentSign)
			haxe.Timer.delay(saveBackup.bind(content), 0);
		currentSign = newSign;
		sys.io.File.saveContent(getPath(), content);
		super.save();
	}

	function updateGrid() {
		if(grid != null) {
			grid.remove();
			grid = null;
		}

		if(!showGrid)
			return;

		grid = new h3d.scene.Graphics(scene.s3d);
		grid.scale(1);
		grid.material.mainPass.setPassName("debuggeom");
		if (gridStep == 0.)
			gridStep = ide.currentConfig.get("sceneeditor.gridStep");
		gridSize = ide.currentConfig.get("sceneeditor.gridSize");

		var col = h3d.Vector.fromColor(scene.engine.backgroundColor);
		var hsl = col.toColorHSL();
		if(hsl.z > 0.5) hsl.z -= 0.1;
		else hsl.z += 0.1;
		col.makeColor(hsl.x, hsl.y, hsl.z);

		grid.lineStyle(1.0, col.toColor(), 1.0);
		for(i in 0...(hxd.Math.floor(gridSize / gridStep) + 1)) {
			grid.moveTo(i * gridStep, 0, 0);
			grid.lineTo(i * gridStep, gridSize, 0);

			grid.moveTo(0, i * gridStep, 0);
			grid.lineTo(gridSize, i * gridStep, 0);
		}
		grid.lineStyle(0);
		grid.setPosition(-1 * gridSize / 2, -1 * gridSize / 2, 0);
	}

	function onUpdate(dt:Float) {
		if(K.isDown(K.ALT)) {
			posToolTip.visible = true;
			var proj = sceneEditor.screenToGround(scene.s2d.mouseX, scene.s2d.mouseY);
			posToolTip.text = proj != null ? '${Math.fmt(proj.x)}, ${Math.fmt(proj.y)}, ${Math.fmt(proj.z)}' : '???';
			posToolTip.setPosition(scene.s2d.mouseX, scene.s2d.mouseY - 12);
		}
		else {
			posToolTip.visible = false;
		}

		if( autoSync && (currentVersion != undo.currentID || lastSyncChange != properties.lastChange) ) {
			save();
			lastSyncChange = properties.lastChange;
			currentVersion = undo.currentID;
		}

	}

	function onRefresh() {
	}

	override function onDragDrop(items : Array<String>, isDrop : Bool) {
		return sceneEditor.onDragDrop(items, isDrop);
	}

	function applyGraphicsFilters(typeid: String, enable: Bool)
	{
		saveDisplayState("graphicsFilters/" + typeid, enable);

		var r : h3d.scene.Renderer = scene.s3d.renderer;

		switch (typeid)
		{
		case "shadows":
			r.shadows = enable;
		default:
		}
	}

	function applySceneFilter(typeid: String, visible: Bool) {
		saveDisplayState("sceneFilters/" + typeid, visible);
		var all = data.flatten(hrt.prefab.Prefab);
		for(p in all) {
			if(p.type == typeid || p.getCdbType() == typeid) {
				sceneEditor.applySceneStyle(p);
			}
		}
	}

	function refreshSceneFilters() {
		var filters : Array<String> = ide.currentConfig.get("sceneeditor.filterTypes");
		filters = filters.copy();
		for(sheet in DataFiles.getAvailableTypes()) {
			filters.push(DataFiles.getTypeName(sheet));
		}
		sceneFilters = new Map();
		for(f in filters) {
			sceneFilters.set(f, getDisplayState("sceneFilters/" + f) != false);
		}
	}

	function initGraphicsFilters() {
		for (typeid in graphicsFilters.keys())
		{
			applyGraphicsFilters(typeid, graphicsFilters.get(typeid));
		}
	}

	function refreshGraphicsFilters() {
		var filters : Array<String> = ["shadows"];
		filters = filters.copy();
		graphicsFilters = new Map();
		for(f in filters) {
			graphicsFilters.set(f, getDisplayState("graphicsFilters/" + f) != false);
		}
	}

	function filtersToMenuItem(filters : Map<String, Bool>, type : String) : Array<hide.comp.ContextMenu.ContextMenuItem> {
		var content : Array<hide.comp.ContextMenu.ContextMenuItem> = [];
		var initDone = false;
		for(typeid in filters.keys()) {
			content.push({label : typeid, checked : filters[typeid], click : function() {
				var on = !filters[typeid];
				filters.set(typeid, on);
				if(initDone)
					switch (type){
						case "Graphics":
							applyGraphicsFilters(typeid, on);
						case "Scene":
							applySceneFilter(typeid, on);
					}

				content.find(function(item) return item.label == typeid).checked = on;
			}});
		}
		initDone = true;
		return content;
	}

	function applyTreeStyle(p: PrefabElement, el: Element, pname: String) {
	}

	function onPrefabChange(p: PrefabElement, ?pname: String) {

	}

	function applySceneStyle(p: PrefabElement) {
		var prefabView = Std.downcast(p, hrt.prefab.Library); // don't use "to" (Reference)
		if( prefabView != null && prefabView.parent == null ) {
			updateGrid();
			return;
		}

		var obj3d = p.to(Object3D);
		if(obj3d != null) {
			var visible = obj3d.visible && !sceneEditor.isHidden(obj3d) && sceneFilters.get(p.type) != false;
			if(visible) {
				var cdbType = p.getCdbType();
				if(cdbType != null && sceneFilters.get(cdbType) == false)
					visible = false;
			}
			for(ctx in sceneEditor.getContexts(obj3d)) {
				ctx.local3d.visible = visible;
			}
		}
		var color = getDisplayColor(p);
		if(color != null){
			color = (color & 0xffffff) | 0xa0000000;
			var box = p.to(hrt.prefab.l3d.Box);
			if(box != null) {
				var ctx = sceneEditor.getContext(box);
				box.setColor(ctx, color);
			}
			var poly = p.to(hrt.prefab.l3d.Polygon);
			if(poly != null) {
				var ctx = sceneEditor.getContext(poly);
				poly.setColor(ctx, color);
			}
		}
	}

	function getDisplayColor(p: PrefabElement) : Null<Int> {
		var typeId = p.getCdbType();
		if(typeId != null) {
			var colors = ide.currentConfig.get("sceneeditor.colors");
			var color = Reflect.field(colors, typeId);
			if(color != null) {
				return Std.parseInt("0x"+color.substr(1)) | 0xff000000;
			}
		}
		return null;
	}

	static var _ = FileTree.registerExtension(Prefab, ["prefab"], { icon : "sitemap", createNew : "Prefab" });
	static var _1 = FileTree.registerExtension(Prefab, ["l3d"], { icon : "sitemap" });

}