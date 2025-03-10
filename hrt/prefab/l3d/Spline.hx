package hrt.prefab.l3d;

import hxd.Math;

enum CurveShape {
	Linear;
	Quadratic;
	Cubic;
}

typedef SplinePointData = {
	pos : h3d.col.Point,
	tangent : h3d.col.Point,
	prev : SplinePoint,
	next : SplinePoint,
	?t : Float
}

class SplineData {
	public var length : Float;
	public var step : Int;
	public var samples : Array<SplinePointData> = [];
	public function new() {}
}

class SplinePointObject extends h3d.scene.Object {
	override function sync(ctx : h3d.scene.RenderContext)
	{
		onSync(ctx);
		super.sync(ctx);
	}

	override function onRemove() {
		super.onRemove();
		onRemoveDynamic();
	}
	public dynamic function onRemoveDynamic() {}
	public dynamic function onSync(rctx: h3d.scene.RenderContext) {}
}

class SplinePoint extends Object3D {

	var pointViewer : h3d.scene.Mesh;
	var controlPointsViewer : h3d.scene.Graphics;
	var indexText : h2d.ObjectFollower;
	var spline(get, default) : Spline;
	var obj : SplinePointObject;
	function get_spline() {
		return parent.to(Spline);
	}

	override public function new(?parent) {
		super(parent);
		type = "splinePoint";
	}

	override function makeInstance(ctx:Context):Context {
		#if editor
		ctx = ctx.clone(this);
		ctx.local3d = createObject(ctx);
		pointViewer = new h3d.scene.Mesh(h3d.prim.Sphere.defaultUnitSphere(), null, ctx.local3d.getScene());
		pointViewer.ignoreParentTransform = true;
		pointViewer.follow = ctx.local3d;
		pointViewer.followPositionOnly = true;
		pointViewer.name = "pointViewer";
		pointViewer.material.setDefaultProps("ui");
		pointViewer.material.color.set(0,0,1,1);
		pointViewer.material.mainPass.depthTest = Always;

		controlPointsViewer = new h3d.scene.Graphics(ctx.local3d);
		controlPointsViewer.name = "controlPointsViewer";
		controlPointsViewer.lineStyle(4, 0xffffff);
		controlPointsViewer.material.mainPass.setPassName("ui");
		controlPointsViewer.material.mainPass.depthTest = Always;
		controlPointsViewer.ignoreParentTransform = false;
		controlPointsViewer.clear();
		controlPointsViewer.moveTo(1, 0, 0);
		controlPointsViewer.lineTo(-1, 0, 0);

		indexText = new h2d.ObjectFollower(pointViewer, ctx.shared.root2d.getScene());
		var t = new h2d.Text(hxd.res.DefaultFont.get(), indexText);
		t.textColor = 0xff00ff;
		t.textAlign = Center;
		t.dropShadow = { dx : 0.5, dy : 0.5, color : 0x202020, alpha : 1.0 };
		t.setScale(2.5);
		applyTransform(ctx.local3d);
		setViewerVisible(false);
		obj = new SplinePointObject(ctx.local3d);
		obj.onSync = function(rctx) {
			var cam = rctx.camera;
			var gpos = obj.getAbsPos().getPosition();
			var distToCam = cam.pos.sub(gpos).length();
			var engine = h3d.Engine.getCurrent();
			var ratio = 18 / engine.height;
			pointViewer.setScale(ratio * distToCam * Math.tan(cam.fovY * 0.5 * Math.PI / 180.0));
			@:privateAccess obj.calcAbsPos();
		}
		obj.onRemoveDynamic = function() {
			indexText.remove();
			pointViewer.remove();
		}
		updateInstance(ctx);
		#end
		return ctx;
	}

	override function applyTransform(o : h3d.scene.Object) {
		super.applyTransform(o);
		#if editor
			if (spline.editor != null)
				@:privateAccess spline.computeSpline(spline.editor.editContext.getContext(spline));
		#end
	}

	override function updateInstance(ctx : Context, ?propName : String) {
		super.updateInstance(ctx, propName);
		#if editor
			if( spline.editor != null ) {
				spline.editor.setSelected(spline.editor.editContext.getContext(spline), true);
				spline.editor.update(spline.editor.editContext.getContext(spline));
			}
			for (sp in spline.points) {
				sp.computeName(ctx);
			}
		#end
	}

	override function removeInstance( ctx : Context) : Bool {
		haxe.Timer.delay(() -> { // wait for next frame, need the point to be removed from children to recompute spline accurately
			#if editor
				if (spline.editor != null && spline.editor.editContext.getContext(spline) != null)
					@:privateAccess spline.computeSpline(spline.editor.editContext.getContext(spline));
			#end
		}, 0);
		return super.removeInstance(ctx);
	}


	#if editor

	public function computeName(ctx) {
		var index = spline.points.indexOf(this);
		name = "SplinePoint" + index;
		ctx.local3d.name = name;
		if (indexText != null) {
			var t = Std.downcast(indexText.getChildAt(0), h2d.Text);
			t.text = "" + index;
		}
	}

	override function edit(ctx : EditContext) {
		super.edit(ctx);
		if( spline.editor == null ) {
			spline.editor = new hide.prefab.SplineEditor(spline, ctx.properties.undo);
		}
		spline.editor.editContext = ctx;
	}
	override function getHideProps() : HideProps {
		return { icon : "arrows-v", name : "SplinePoint", allowParent: function(p) return p.to(Spline) != null, allowChildren: function(s) return false};
	}
	#end

	inline public function getPoint() : h3d.col.Point {
		return getAbsPos().getPosition().toPoint();
	}

	public function getTangent() : h3d.col.Point {
		var tangent = getAbsPos().front().toPoint();
		tangent.scale(-1);
		return tangent;
	}

	public function getFirstControlPoint() : h3d.col.Point {
		var absPos = getAbsPos();
		var right = absPos.front();
		right.scale3(scaleX*scaleY);
		var pos = new h3d.col.Point(absPos.tx, absPos.ty, absPos.tz);
		pos = pos.add(right.toPoint());
		return pos;
	}

	public function getSecondControlPoint() : h3d.col.Point {
		var absPos = getAbsPos();
		var left = absPos.front();
		left.scale3(-scaleX*scaleZ);
		var pos = new h3d.col.Point(absPos.tx, absPos.ty, absPos.tz);
		pos = pos.add(left.toPoint());
		return pos;
	}
	public function setViewerVisible(visible : Bool) {
		pointViewer.visible = visible;
		indexText.visible = visible;
		controlPointsViewer.visible = visible;
	}
	public function setColor( color : Int ) {
		controlPointsViewer.setColor(color);
		pointViewer.material.color.setColor(color);
	}

	static var _ = hrt.prefab.Library.register("splinePoint", SplinePoint);
}

class Spline extends Object3D {
	public var points(get, null) : Array<SplinePoint>;
	function get_points() {
		var pts : Array<SplinePoint> = [];
		for (c in children) {
			var sp = c.to(SplinePoint);
			if (sp != null) pts.push(sp);
		}
		return pts;
	}

	@:c public var shape : CurveShape = Linear;

	var data : SplineData;
	@:s var step : Int = 1;

	// Save/Load the curve as an array of local transform
	@:c public var pointsData : Array<h3d.Matrix> = [];

	// Graphic
	@:s public var showSpline : Bool = true;
	public var lineGraphics : h3d.scene.Graphics;
	@:s public var lineThickness : Int = 4;
	@:s public var color : Int = 0xFFFFFFFF;
	@:s public var loop : Bool = false;

	#if editor
	public var editor : hide.prefab.SplineEditor;
	#end
	public var wasEdited = false;

	override function save() {
		var obj : Dynamic = super.save();

		obj.shape = shape.getIndex();
		return obj;
	}

	override function load( obj : Dynamic ) {
		super.load(obj);

		// Backward compatibility
		pointsData = [];
		if( obj.points != null ) {
			var points : Array<Dynamic> = obj.points;
			for( p in points ) {
				var m = new h3d.Matrix();
				m.loadValues(p);
				pointsData.push(m);
			}
		}
		shape = obj.shape == null ? Linear : CurveShape.createByIndex(obj.shape);
	}

	// Generate the splineData from a matrix, can't move the spline after that
	public function makeFromMatrix( m : h3d.Matrix ) {
		var tmp = new h3d.Matrix();
		points = [];
		for( pd in pointsData ) {
			var sp = new SplinePoint(this);
			tmp.load(pd);
			tmp.multiply(tmp, m);
			sp.setTransform(tmp);
			sp.getAbsPos();
		}
		computeSplineData();
	}


	override function makeInstance( ctx : hrt.prefab.Context ) : hrt.prefab.Context {
		var ctx = ctx.clone(this);
		ctx.local3d = createObject(ctx);
		ctx.local3d.name = name;

		// Backward compatibility
		for( pd in pointsData ) {
			var sp = new SplinePoint(this);
			sp.setTransform(pd);
			sp.getAbsPos();
		}

		if( points.length == 0 )
			new SplinePoint(this);

		updateInstance(ctx);
		return ctx;
	}

	override function updateInstance( ctx : hrt.prefab.Context , ?propName : String ) {
		super.updateInstance(ctx, propName);
		#if editor
		if( editor != null )
			editor.update(ctx, propName);
		#end
		computeSpline(ctx);
	}

	// Return an interpolation of two samples at t, 0 <= t <= 1
	public function getPointAt( t : Float, ?pos: h3d.col.Point, ?tangent: h3d.col.Point ) : h3d.col.Point {
		if( data == null )
			computeSplineData();

		// The last point is not at the same distance, be aware of that case
		t = hxd.Math.clamp(t);
		var l = t * (data.samples.length - 1);
		var s1 : Int = hxd.Math.floor(l);
		var s2 : Int = hxd.Math.ceil(l);
		s1 = hxd.Math.iclamp(s1, 0, data.samples.length - 1);
		s2 = hxd.Math.iclamp(s2, 0, data.samples.length - 1);

		if(pos == null)
			pos = new h3d.col.Point();

		// End/Beginning of the curve, just return the point
		if( s1 == s2 ) {
			pos.load(data.samples[s1].pos);
			if(tangent != null)
				tangent.load(data.samples[s1].tangent);
		}
		// Linear interpolation between the two samples
		else {
			var segmentLength = data.samples[s1].pos.distance(data.samples[s2].pos);
			if (segmentLength == 0) {
				pos.load(data.samples[s1].pos);
				if(tangent != null)
					tangent.load(data.samples[s1].tangent);
			}
			else {
				var t = (l - s1) / segmentLength;
				pos.lerp(data.samples[s1].pos, data.samples[s2].pos, t);
				if(tangent != null)
					tangent.lerp(data.samples[s1].tangent, data.samples[s2].tangent, t);
			}

		}
		return pos;
	}

	// Return the euclidean distance between the two points
	inline function getMaxLengthBetween( p1 : SplinePoint, p2 : SplinePoint) : Float {
		switch shape {
			case Linear: return p1.getPoint().distance(p2.getPoint());
			case Quadratic: return p1.getPoint().distance(p1.getSecondControlPoint()) + p1.getFirstControlPoint().distance(p2.getPoint());
			case Cubic: return p1.getPoint().distance(p1.getSecondControlPoint()) + p1.getFirstControlPoint().distance(p2.getFirstControlPoint()) + p2.getFirstControlPoint().distance(p2.getPoint());
		}
	}

	// Return the sum of the euclidean distances between each control points
	inline function getMinLengthBetween( p1 : SplinePoint, p2 : SplinePoint) : Float {
		return p1.getPoint().distance(p2.getPoint());
	}

	// Return the sum of the euclidean distances between each samples
	public function getLength() {
		if( data == null )
			computeSplineData();
		return data.length;
	}

	// Sample the spline with the step
	function computeSplineData() {

		var sd = new SplineData();
		data = sd;

		if( step <= 0 )
			return;

		if( points == null || points.length <= 1 )
			return;

		// Sample the spline
		var samples : Array<SplinePointData> = [{ pos : points[0].getPoint(), tangent : points[0].getTangent(), prev : points[0], next : points[1] }];
		var maxI = loop ? points.length : points.length - 1;
		var curP = points[0];
		var nextP = points[1];
		for (i in 1...maxI + 1) {
			var t = 0.;
			while (t <= 1.) {
				var p = getPointBetween(t, curP, nextP);
				if (p.distance(samples[samples.length - 1].pos) >= 1./step)
					samples.insert(samples.length, { pos : p, tangent : getTangentBetween(t, curP, nextP), prev : curP, next : nextP });
				t += 1./step;
			}
			if (nextP.getPoint().distance(samples[samples.length - 1].pos) >= 1./step)
				samples.insert(samples.length, { pos : nextP.getPoint(), tangent : nextP.getTangent(), prev : curP, next : nextP });
			curP = points[i];
			nextP = points[(i + 1) % points.length];

		}
		sd.samples = samples;

		// Compute the average length of the spline
		var lengthSum = 0.0;
		for( i in 0 ... samples.length - 1 ) {
			lengthSum += samples[i].pos.distance(samples[i+1].pos);
		}
		var l = 0.0;
		for( i in 0 ... samples.length - 1 ) {
			samples[i].t = l/lengthSum;
			l += samples[i].pos.distance(samples[i+1].pos);
		}
		samples[samples.length - 1].t = 1;
		sd.length = lengthSum;
	}

	// Return the closest spline point on the spline from p
	function getClosestSplinePoint( p : h3d.col.Point ) : SplinePoint {
		var minDist = -1.0;
		var curPt : SplinePoint = null;
		for( sp in points ) {
			var dist = p.distance(sp.getPoint());
			if( dist < minDist || minDist == -1 ) {
				minDist = dist;
				curPt = sp;
			}
		}
		return curPt;
	}

	public function getSplinePointDataAt( t : Float) : SplinePointData {
		if( data == null )
			computeSplineData();

		var minDist = -1.0;
		var result : SplinePointData = null;
		for( s in data.samples ) {
			var dist = Math.abs(s.t - t);
			if( dist < minDist || minDist == -1 ) {
				minDist = dist;
				result = s;
			}
		}
		return result;
	}

	// Return the closest point on the spline from p
	function getClosestPoint( p : h3d.col.Point ) : SplinePointData {

		if( data == null )
			computeSplineData();

		var minDist = -1.0;
		var result : SplinePointData = null;
		for( s in data.samples ) {
			var dist = s.pos.distance(p);
			if( dist < minDist || minDist == -1 ) {
				minDist = dist;
				result = s;
			}
		}
		return result;
	}

	// Return the point on the curve between p1 and p2 at t, 0 <= t <= 1
	inline function getPointBetween( t : Float, p1 : SplinePoint, p2 : SplinePoint ) : h3d.col.Point {
		return switch (shape) {
			case Linear: getLinearBezierPoint( t, p1.getPoint(), p2.getPoint() );
			case Quadratic: getQuadraticBezierPoint( t, p1.getPoint(), p1.getSecondControlPoint(), p2.getPoint() );
			case Cubic: getCubicBezierPoint( t, p1.getPoint(), p1.getSecondControlPoint(), p2.getFirstControlPoint(), p2.getPoint() );
		}
	}

	// Return the tangent on the curve between p1 and p2 at t, 0 <= t <= 1
	inline function getTangentBetween( t : Float, p1 : SplinePoint, p2 : SplinePoint ) : h3d.col.Point {
		return switch (shape) {
			case Linear: getLinearBezierTangent( t, p1.getPoint(), p2.getPoint() );
			case Quadratic: getQuadraticBezierTangent( t, p1.getPoint(), p1.getSecondControlPoint(), p2.getPoint() );
			case Cubic: getCubicBezierTangent( t, p1.getPoint(), p1.getSecondControlPoint(), p2.getFirstControlPoint(), p2.getPoint() );
		}
	}

	// Linear Interpolation
	// p(t) = p0 + (p1 - p0) * t
	inline function getLinearBezierPoint( t : Float, p0 : h3d.col.Point, p1 : h3d.col.Point ) : h3d.col.Point {
		return p0.add((p1.sub(p0).multiply(t)));
	}
	// p'(t) = (p1 - p0)
	inline function getLinearBezierTangent( t : Float, p0 : h3d.col.Point, p1 : h3d.col.Point ) : h3d.col.Point {
		return p1.sub(p0).normalized();
	}

	// Quadratic Interpolation
	// p(t) = p0 * (1 - t)² + p1 * t * 2 * (1 - t) + p2 * t²
	inline function getQuadraticBezierPoint( t : Float, p0 : h3d.col.Point, p1 : h3d.col.Point, p2 : h3d.col.Point) : h3d.col.Point {
		return p0.multiply((1 - t) * (1 - t)).add(p1.multiply(t * 2 * (1 - t))).add(p2.multiply(t * t));
	}
	// p'(t) = 2 * (1 - t) * (p1 - p0) + 2 * t * (p2 - p1)
	inline function getQuadraticBezierTangent( t : Float, p0 : h3d.col.Point, p1 : h3d.col.Point, p2 : h3d.col.Point) : h3d.col.Point {
		return p1.sub(p0).multiply(2 * (1 - t)).add(p2.sub(p1).multiply(2 * t)).normalized();
	}

	// Cubic Interpolation
	// p(t) = p0 * (1 - t)³ + p1 * t * 3 * (1 - t)² + p2 * t² * 3 * (1 - t) + p3 * t³
	inline function getCubicBezierPoint( t : Float, p0 : h3d.col.Point, p1 : h3d.col.Point, p2 : h3d.col.Point, p3 : h3d.col.Point) : h3d.col.Point {
		return p0.multiply((1 - t) * (1 - t) * (1 - t)).add(p1.multiply(t * 3 * (1 - t) * (1 - t))).add(p2.multiply(t * t * 3 * (1 - t))).add(p3.multiply(t * t * t));
	}
	// p'(t) = 3 * (1 - t)² * (p1 - p0) + 6 * (1 - t) * t * (p2 - p1) + 3 * t² * (p3 - p2)
	inline function getCubicBezierTangent( t : Float, p0 : h3d.col.Point, p1 : h3d.col.Point, p2 : h3d.col.Point, p3 : h3d.col.Point) : h3d.col.Point {
		return p1.sub(p0).multiply(3 * (1 - t) * (1 - t)).add(p2.sub(p1).multiply(6 * (1 - t) * t)).add(p3.sub(p2).multiply(3 * t * t)).normalized();
	}

	function generateSplineGraph( ctx : hrt.prefab.Context ) {

		if( !showSpline ) {
			if( lineGraphics != null ) {
				lineGraphics.remove();
				lineGraphics = null;
			}
			return;
		}

		if( lineGraphics == null ) {
			lineGraphics = new h3d.scene.Graphics(ctx.local3d);
			lineGraphics.lineStyle(lineThickness, color);
			lineGraphics.material.mainPass.setPassName("overlay");
			lineGraphics.material.mainPass.depth(false, LessEqual);
			lineGraphics.ignoreParentTransform = false;
		}

		lineGraphics.lineStyle(lineThickness, color);
		lineGraphics.clear();
		var b = true;
		for( s in data.samples ) {
			var localPos = ctx.local3d.globalToLocal(s.pos.clone());
			b ? lineGraphics.moveTo(localPos.x, localPos.y, localPos.z) : lineGraphics.lineTo(localPos.x, localPos.y, localPos.z);
			b = false;
		}
	}

	public function computeSpline(ctx : hrt.prefab.Context) {
		computeSplineData();
		#if editor
			generateSplineGraph(ctx);
		#end
	}

	#if editor

	public function onEdit( b : Bool ) {
		if( b ) wasEdited = true;
	}

	override function setSelected( ctx : hrt.prefab.Context , b : Bool ) {
		super.setSelected(ctx, b);

		if( editor != null )
			editor.setSelected(ctx, b);

		return true;
	}

	override function edit( ctx : EditContext ) {
		super.edit(ctx);

		ctx.properties.add( new hide.Element('
			<div class="group" name="Spline">
				<dl>
					<dt>Color</dt><dd><input type="color" alpha="true" field="color"/></dd>
					<dt>Thickness</dt><dd><input type="range" min="1" max="10" field="lineThickness"/></dd>
					<dt>Step</dt><dd><input type="range" min="1" max="10" step="1" field="step"/></dd>
					<dt>Loop</dt><dd><input type="checkbox" field="loop"/></dd>
					<dt>Show Spline</dt><dd><input type="checkbox" field="showSpline"/></dd>
					<dt>Type</dt>
						<dd>
							<select field="shape" >
								<option value="Linear">Linear</option>
								<option value="Cubic">Curve</option>
							</select>
						</dd>
				</dl>
			</div>'), this, function(pname) { ctx.onChange(this, pname); });

		if( editor == null ) {
			editor = new hide.prefab.SplineEditor(this, ctx.properties.undo);
		}

		editor.editContext = ctx;
		editor.edit(ctx);
	}

	override function getHideProps() : HideProps {
		return { icon : "arrows-v", name : "Spline", allowChildren: function(s) return Library.isOfType(s, SplinePoint) };
	}
	#end

	static var _ = hrt.prefab.Library.register("spline", Spline);
}