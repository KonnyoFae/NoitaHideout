-- Times are game frames, radii are world pixels, healing is in displayed HP.
return {
    {id="fire",zh="火力",en="Firepower",costs={1,2,3,5}},
    {id="scout",zh="侦查",en="Recon",costs={2,3,4,5},
        radius={30,44,60,88},life={90,132,174,216},mark={90,150,210,270},bounces={3,5,7,0}},
    {id="aid",zh="辅助",en="Support",costs={2,4,6,8},
        radius={32,46,60,78},life={180,240,300,420},healPerSecond={4,6,8,14}},
    {id="move",zh="机动",en="Mobility",costs={2,1}},
}
