/*
 *  ViewPlacementGenerator.mm
 *  WhirlyGlobeLib
 *
 *  Created by Steve Gifford on 7/25/12.
 *  Copyright 2011-2012 mousebird consulting
 *
 *  Licensed under the Apache License, Version 2.0 (the "License");
 *  you may not use this file except in compliance with the License.
 *  You may obtain a copy of the License at
 *  http://www.apache.org/licenses/LICENSE-2.0
 *
 *  Unless required by applicable law or agreed to in writing, software
 *  distributed under the License is distributed on an "AS IS" BASIS,
 *  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 *  See the License for the specific language governing permissions and
 *  limitations under the License.
 *
 */

#import "ViewPlacementGenerator.h"

using namespace Eigen;
using namespace WhirlyKit;
using namespace WhirlyGlobe;

namespace WhirlyKit
{
    
ViewPlacementGenerator::ViewPlacementGenerator(const std::string &name)
    : Generator(name)
{
}
    
ViewPlacementGenerator::~ViewPlacementGenerator()
{
    viewInstanceSet.clear();
}
    
void ViewPlacementGenerator::addView(GeoCoord loc,UIView *view,float minVis,float maxVis)
{
    // Make sure it isn't already there
    removeView(view);
    
    ViewInstance viewInst(loc,view);
    viewInst.minVis = minVis;
    viewInst.maxVis = maxVis;
    viewInstanceSet.insert(viewInst);
}
    
void ViewPlacementGenerator::removeView(UIView *view)
{
    std::set<ViewInstance>::iterator it = viewInstanceSet.find(ViewInstance(view));
    if (it != viewInstanceSet.end())
        viewInstanceSet.erase(it);
}
    
// Work through the list of views, moving things around and/or hiding as needed
void ViewPlacementGenerator::generateDrawables(WhirlyKitRendererFrameInfo *frameInfo,std::vector<DrawableRef> &drawables,std::vector<DrawableRef> &screenDrawables)
{
    CoordSystem *coordSys = frameInfo.scene->getCoordSystem();
    
    // Note: Make this work for generic 3D views
    WhirlyGlobeView *globeView = (WhirlyGlobeView *)frameInfo.theView;
    if (![globeView isKindOfClass:[WhirlyGlobeView class]])
        return;

    // Overall extents we'll look at.  Everything else is tossed.
    // Note: This is too simple
    Mbr frameMbr;
    float marginX = frameInfo.sceneRenderer.framebufferWidth * 1.1;
    float marginY = frameInfo.sceneRenderer.framebufferHeight * 1.1;
    frameMbr.ll() = Point2f(0 - marginX,0 - marginY);
    frameMbr.ur() = Point2f(frameInfo.sceneRenderer.framebufferWidth + marginX,frameInfo.sceneRenderer.framebufferHeight + marginY);
    
    for (std::set<ViewInstance>::iterator it = viewInstanceSet.begin();
         it != viewInstanceSet.end(); ++it)
    {
        const ViewInstance &viewInst = *it;
        bool hidden = NO;
        CGPoint screenPt;
        
        // Height above globe test
        float visVal = [frameInfo.theView heightAboveSurface];
        if (!(viewInst.minVis == DrawVisibleInvalid || viewInst.maxVis == DrawVisibleInvalid ||
              ((viewInst.minVis <= visVal && visVal <= viewInst.maxVis) ||
               (viewInst.maxVis <= visVal && visVal <= viewInst.minVis))))
            hidden = YES;

        if (!hidden)
        {
            // Note: Calculate this ahead of time
            Point3f worldLoc = coordSys->localToGeocentricish(coordSys->geographicToLocal(viewInst.loc));
            
            // Note: Copied from the ScreenSpaceGenerator.  Still dumb here.
            Point3f testPts[2];
            testPts[0] = worldLoc;
            testPts[1] = worldLoc*1.5;
            for (unsigned int ii=0;ii<2;ii++)
            {
                Vector4f modelSpacePt = frameInfo.viewAndModelMat * Vector4f(testPts[ii].x(),testPts[ii].y(),testPts[ii].z(),1.0);
                modelSpacePt.x() /= modelSpacePt.w();  modelSpacePt.y() /= modelSpacePt.w();  modelSpacePt.z() /= modelSpacePt.w();  modelSpacePt.w() = 1.0;
                Vector4f projSpacePt = frameInfo.projMat * Vector4f(modelSpacePt.x(),modelSpacePt.y(),modelSpacePt.z(),modelSpacePt.w());
                //        projSpacePt.x() /= projSpacePt.w();  projSpacePt.y() /= projSpacePt.w();  projSpacePt.z() /= projSpacePt.w();  projSpacePt.w() = 1.0;
                testPts[ii] = Point3f(projSpacePt.x(),projSpacePt.y(),projSpacePt.z());
            }
            Vector3f testDir = testPts[1] - testPts[0];
            testDir.normalize();

            // Note: This is so dumb it hurts.  Figure out why the math is broken.
            if (testDir.z() > -0.33)
                hidden = YES;

            // If it's pointed away from the user, don't bother
//            if (worldLoc.dot(frameInfo.eyeVec) < 0.0)
//                hidden = YES;

            if (!hidden)
            {
                // Project the world location to the screen
                Eigen::Matrix4f modelTrans = frameInfo.modelTrans;
                screenPt = [globeView pointOnScreenFromSphere:worldLoc transform:&modelTrans frameSize:Point2f(frameInfo.sceneRenderer.framebufferWidth,frameInfo.sceneRenderer.framebufferHeight)]; 
                
                // Note: This check is too simple
                if (!hidden &&
                    (screenPt.x < frameMbr.ll().x() || screenPt.y < frameMbr.ll().y() || 
                     screenPt.x > frameMbr.ur().x() || screenPt.y > frameMbr.ur().y()))
                    hidden = YES;
            }
        }
        
        viewInst.view.hidden = hidden;
        if (!hidden)
        {
            CGSize size = viewInst.view.frame.size;
            viewInst.view.frame = CGRectMake(screenPt.x, screenPt.y, size.width, size.height);
        }
    }
}

}
